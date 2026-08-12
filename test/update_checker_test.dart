import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/update/update_checker.dart';
import 'package:pub_semver/pub_semver.dart';

Future<HttpServer> _serveJson(Object json) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(_serve(server, json));
  return server;
}

Future<void> _serve(HttpServer server, Object payload) async {
  await for (final req in server) {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(payload));
    await req.response.close();
  }
}

void main() {
  test('default manifest points at the PUBLIC mirror repo, not the source repo',
      () {
    // The source repo goes private, so the update check must target the
    // public `lanlink-downloads` mirror. Guard against silently reverting it.
    expect(UpdateChecker.defaultManifestUrl, contains('lanlink-downloads'));
    expect(
      UpdateChecker.defaultManifestUrl,
      isNot(endsWith('/lanlink/releases')),
    );
  });

  test('UpdateChecker resolves a windows .exe asset as the Windows download',
      () async {
    final server = await _serveJson([
      {
        'tag_name': 'v3.1.0',
        'name': 'v3.1.0',
        'html_url': '',
        'body': '',
        'prerelease': false,
        'draft': false,
        'published_at': '2025-01-01T00:00:00Z',
        'assets': [
          {
            'name': 'lanlink-windows-setup.exe',
            'browser_download_url': 'https://example.test/lanlink-setup.exe',
          },
        ],
      },
    ]);
    addTearDown(() => server.close(force: true));
    final url = 'http://${server.address.address}:${server.port}/releases';
    final checker = UpdateChecker(manifestUrl: url);
    addTearDown(checker.dispose);
    _setCurrent(checker, Version.parse('3.0.0'));
    await checker.checkNow();
    expect(checker.availableUpdate?.windowsAssetUrl, endsWith('.exe'));
  });

  test('UpdateChecker prefers the universal APK over ABI-specific APKs',
      () async {
    final server = await _serveJson([
      {
        'tag_name': 'v3.1.0',
        'name': 'v3.1.0',
        'html_url': '',
        'body': '',
        'prerelease': false,
        'draft': false,
        'published_at': '2025-01-01T00:00:00Z',
        // GitHub currently returns LanLink's arm64 asset before universal.
        // Offering that APK to an x86_64 or 32-bit device fails to install.
        'assets': [
          {
            'name': 'lanlink-v3.1.0-arm64-v8a.apk',
            'browser_download_url':
                'https://example.test/lanlink-v3.1.0-arm64-v8a.apk',
          },
          {
            'name': 'lanlink-v3.1.0-armeabi-v7a.apk',
            'browser_download_url':
                'https://example.test/lanlink-v3.1.0-armeabi-v7a.apk',
          },
          {
            'name': 'lanlink-v3.1.0-universal.apk',
            'browser_download_url':
                'https://example.test/lanlink-v3.1.0-universal.apk',
          },
        ],
      },
    ]);
    addTearDown(() => server.close(force: true));
    final url = 'http://${server.address.address}:${server.port}/releases';
    final checker = UpdateChecker(manifestUrl: url);
    addTearDown(checker.dispose);
    _setCurrent(checker, Version.parse('3.0.0'));

    await checker.checkNow();

    expect(
        checker.availableUpdate?.androidAssetUrl, endsWith('-universal.apk'));
  });

  test(
      'UpdateChecker reports an update when the latest tag is greater than current',
      () async {
    final server = await _serveJson([
      {
        'tag_name': 'v2.5.0',
        'name': 'v2.5.0',
        'html_url': 'https://example.test/r/v2.5.0',
        'body': 'Major release',
        'prerelease': false,
        'draft': false,
        'published_at': '2025-01-01T00:00:00Z',
        'assets': [
          {
            'name': 'lanlink-2.5.0-android.apk',
            'browser_download_url':
                'https://example.test/r/v2.5.0/lanlink-2.5.0-android.apk',
          },
          {
            'name': 'lanlink-2.5.0-windows.zip',
            'browser_download_url':
                'https://example.test/r/v2.5.0/lanlink-2.5.0-windows.zip',
          },
          {
            'name': 'lanlink-2.5.0-linux-x64.tar.gz',
            'browser_download_url':
                'https://example.test/r/v2.5.0/lanlink-2.5.0-linux-x64.tar.gz',
          },
          {
            'name': 'LanLink-2.5.0-x86_64.AppImage',
            'browser_download_url':
                'https://example.test/r/v2.5.0/LanLink-2.5.0-x86_64.AppImage',
          },
        ],
      },
      {
        'tag_name': 'v2.0.0',
        'name': 'v2.0.0',
        'html_url': 'https://example.test/r/v2.0.0',
        'body': 'Old',
        'prerelease': false,
        'draft': false,
        'published_at': '2024-01-01T00:00:00Z',
        'assets': const [],
      },
    ]);
    addTearDown(() => server.close(force: true));

    final url = 'http://${server.address.address}:${server.port}/releases';
    final checker = UpdateChecker(manifestUrl: url);
    addTearDown(checker.dispose);

    await checker.checkNow();

    expect(checker.availableUpdate, isNull,
        reason: 'currentVersion is unknown until initialize, '
            'so we should not surface an update');

    // Simulate the bootstrap path where currentVersion gets set, but use a
    // version we control instead of PackageInfo.fromPlatform (which has no
    // value in a unit test on the VM).
    final viaReflection = _setCurrent(checker, Version.parse('2.0.0'));
    expect(viaReflection, isTrue);
    await checker.checkNow();

    final update = checker.availableUpdate;
    expect(update, isNotNull);
    expect(update!.tagName, 'v2.5.0');
    expect(update.androidAssetUrl, contains('android.apk'));
    expect(update.windowsAssetUrl, contains('windows.zip'));
    expect(update.linuxAssetUrl, contains('.AppImage'),
        reason: 'the AppImage should win over the tar.gz when both exist');
  });

  test('UpdateChecker stays quiet when the newest tag is the current version',
      () async {
    final server = await _serveJson([
      {
        'tag_name': 'v3.1.0',
        'name': 'v3.1.0',
        'html_url': '',
        'body': '',
        'prerelease': false,
        'draft': false,
        'published_at': '2025-01-01T00:00:00Z',
        'assets': const [],
      },
    ]);
    addTearDown(() => server.close(force: true));

    final url = 'http://${server.address.address}:${server.port}/releases';
    final checker = UpdateChecker(manifestUrl: url);
    addTearDown(checker.dispose);

    _setCurrent(checker, Version.parse('3.1.0'));
    await checker.checkNow();
    expect(checker.availableUpdate, isNull);
  });

  test('UpdateChecker skips drafts', () async {
    final server = await _serveJson([
      {
        'tag_name': 'v9.9.9',
        'name': 'v9.9.9',
        'html_url': '',
        'body': '',
        'prerelease': false,
        'draft': true,
        'published_at': '2025-01-01T00:00:00Z',
        'assets': const [],
      },
      {
        'tag_name': 'v1.0.0',
        'name': 'v1.0.0',
        'html_url': '',
        'body': '',
        'prerelease': false,
        'draft': false,
        'published_at': '2024-01-01T00:00:00Z',
        'assets': const [],
      },
    ]);
    addTearDown(() => server.close(force: true));

    final url = 'http://${server.address.address}:${server.port}/releases';
    final checker = UpdateChecker(manifestUrl: url);
    addTearDown(checker.dispose);

    _setCurrent(checker, Version.parse('0.9.0'));
    await checker.checkNow();
    final update = checker.availableUpdate;
    expect(update, isNotNull);
    expect(update!.tagName, 'v1.0.0', reason: 'draft v9.9.9 must be ignored');
  });

  List<Object> mixedStableAndPrereleaseManifest() => [
        {
          'tag_name': 'v3.0.0-beta.1',
          'name': 'v3.0.0-beta.1',
          'html_url': '',
          'body': '',
          'prerelease': true,
          'draft': false,
          'published_at': '2025-02-01T00:00:00Z',
          'assets': const [],
        },
        {
          'tag_name': 'v2.5.0',
          'name': 'v2.5.0',
          'html_url': '',
          'body': '',
          'prerelease': false,
          'draft': false,
          'published_at': '2025-01-01T00:00:00Z',
          'assets': const [],
        },
      ];

  test('by default, a newer prerelease is skipped in favour of older stable',
      () async {
    final server = await _serveJson(mixedStableAndPrereleaseManifest());
    addTearDown(() => server.close(force: true));

    final url = 'http://${server.address.address}:${server.port}/releases';
    final checker = UpdateChecker(manifestUrl: url);
    addTearDown(checker.dispose);

    _setCurrent(checker, Version.parse('2.0.0'));
    await checker.checkNow();
    final update = checker.availableUpdate;
    expect(update, isNotNull);
    expect(update!.tagName, 'v2.5.0',
        reason: 'production builds must not be offered v3.0.0-beta.1');
  });

  test('includePrereleases: true opts back in to prerelease updates', () async {
    final server = await _serveJson(mixedStableAndPrereleaseManifest());
    addTearDown(() => server.close(force: true));

    final url = 'http://${server.address.address}:${server.port}/releases';
    final checker = UpdateChecker(manifestUrl: url, includePrereleases: true);
    addTearDown(checker.dispose);

    _setCurrent(checker, Version.parse('2.0.0'));
    await checker.checkNow();
    final update = checker.availableUpdate;
    expect(update, isNotNull);
    expect(update!.tagName, 'v3.0.0-beta.1');
  });
}

/// Test helper: poke `_currentVersion` without exposing it publicly so the
/// production code stays clean.
bool _setCurrent(UpdateChecker checker, Version version) {
  try {
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    (checker as dynamic).debugSetCurrentVersion(version);
    return true;
  } catch (_) {
    return false;
  }
}
