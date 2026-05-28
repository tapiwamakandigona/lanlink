import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

/// One available release fetched from the manifest.
@immutable
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    required this.body,
    required this.androidAssetUrl,
    required this.windowsAssetUrl,
    required this.macosAssetUrl,
    required this.iosAssetUrl,
    required this.publishedAt,
    required this.isPrerelease,
  });

  final Version version;
  final String tagName;
  final String htmlUrl;
  final String body;
  final String? androidAssetUrl;
  final String? windowsAssetUrl;
  final String? macosAssetUrl;
  final String? iosAssetUrl;
  final DateTime publishedAt;
  final bool isPrerelease;

  /// Best download URL for the current platform, or null if the release
  /// doesn't ship a build for it.
  String? get downloadUrlForCurrentPlatform {
    if (Platform.isAndroid) return androidAssetUrl;
    if (Platform.isWindows) return windowsAssetUrl;
    if (Platform.isMacOS) return macosAssetUrl;
    if (Platform.isIOS) return iosAssetUrl;
    return null;
  }
}

/// Polls the LanLink update manifest (GitHub Releases API by default) and
/// exposes the latest available release as a [ChangeNotifier].
///
/// The check is cheap and silent on failure: no toast/log spam if the user
/// is offline. The UI just doesn't show the "Update available" banner.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({
    String? manifestUrl,
    bool includePrereleases = true,
    HttpClient? httpClient,
  })  : _manifestUrl = manifestUrl ?? _defaultManifestUrl,
        _includePrereleases = includePrereleases,
        _client = httpClient ?? HttpClient();

  static const _defaultManifestUrl =
      'https://api.github.com/repos/tapiwamakandigona/lanlink/releases';

  final String _manifestUrl;
  final bool _includePrereleases;
  final HttpClient _client;

  ReleaseInfo? _latest;
  Version? _currentVersion;
  DateTime? _lastCheckedAt;
  bool _checking = false;

  /// The newest release whose version is strictly greater than the running
  /// app's version. `null` when no newer release exists or we haven't
  /// fetched yet.
  ReleaseInfo? get availableUpdate {
    final latest = _latest;
    final current = _currentVersion;
    if (latest == null || current == null) return null;
    if (latest.version > current) return latest;
    return null;
  }

  Version? get currentVersion => _currentVersion;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  bool get isChecking => _checking;

  /// Test hook: lets unit tests stub out the running app version without
  /// having to fake `PackageInfo.fromPlatform`. Production code should never
  /// call this.
  @visibleForTesting
  void debugSetCurrentVersion(Version version) {
    _currentVersion = version;
    notifyListeners();
  }

  /// Loads the current app version and kicks off the first check. Safe to
  /// call multiple times; subsequent calls just trigger a fresh poll.
  Future<void> initialize() async {
    if (_currentVersion == null) {
      try {
        final info = await PackageInfo.fromPlatform();
        _currentVersion = _parseVersion(info.version);
      } catch (e) {
        if (kDebugMode) debugPrint('[update] PackageInfo failed: $e');
      }
    }
    await checkNow();
  }

  /// Forces a fresh fetch of the manifest. Honoured even if a previous
  /// check is still in flight (it queues behind it).
  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    notifyListeners();
    try {
      final releases = await _fetchReleases();
      if (releases.isEmpty) return;
      final latest = releases.first;
      _latest = latest;
      _lastCheckedAt = DateTime.now();
    } catch (e) {
      if (kDebugMode) debugPrint('[update] fetch failed: $e');
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<List<ReleaseInfo>> _fetchReleases() async {
    final uri = Uri.parse(_manifestUrl);
    final req = await _client.getUrl(uri);
    req.headers.add(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    req.headers.add('User-Agent', 'LanLink-UpdateChecker');
    final resp = await req.close().timeout(const Duration(seconds: 8));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('Manifest HTTP ${resp.statusCode}', uri: uri);
    }
    final body = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    final decoded = json.decode(body);
    final list = decoded is List ? decoded : [decoded];
    final releases = <ReleaseInfo>[];
    for (final entry in list) {
      if (entry is! Map<String, dynamic>) continue;
      final isPrerelease = entry['prerelease'] == true;
      if (isPrerelease && !_includePrereleases) continue;
      if (entry['draft'] == true) continue;
      final tag = entry['tag_name'] as String? ?? '';
      final version = _parseVersion(tag);
      if (version == null) continue;
      final assets = (entry['assets'] as List?) ?? const [];
      String? android, windows, macos, ios;
      for (final raw in assets) {
        if (raw is! Map<String, dynamic>) continue;
        final name = (raw['name'] as String? ?? '').toLowerCase();
        final url = raw['browser_download_url'] as String? ?? '';
        if (name.endsWith('.apk')) android ??= url;
        if (name.contains('windows') && name.endsWith('.zip')) {
          windows ??= url;
        }
        if (name.endsWith('.dmg') ||
            (name.contains('macos') && name.endsWith('.zip'))) {
          macos ??= url;
        }
        if (name.endsWith('.ipa') ||
            (name.contains('ios') && name.endsWith('.zip'))) {
          ios ??= url;
        }
      }
      releases.add(ReleaseInfo(
        version: version,
        tagName: tag,
        htmlUrl: entry['html_url'] as String? ?? '',
        body: entry['body'] as String? ?? '',
        androidAssetUrl: android,
        windowsAssetUrl: windows,
        macosAssetUrl: macos,
        iosAssetUrl: ios,
        publishedAt:
            DateTime.tryParse(entry['published_at'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        isPrerelease: isPrerelease,
      ));
    }
    releases.sort((a, b) => b.version.compareTo(a.version));
    return releases;
  }

  static Version? _parseVersion(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1);
    }
    try {
      return Version.parse(cleaned);
    } catch (_) {
      return null;
    }
  }
}
