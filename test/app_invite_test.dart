import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/app_invite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lanlink/app_invite');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    AppInvite.debugIsSupportedOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('AppInvite.apkFileName', () {
    test('stamps the version into the shared file name', () {
      expect(AppInvite.apkFileName('4.1.0'), 'LanLink-v4.1.0.apk');
      expect(AppInvite.apkFileName('10.2.3'), 'LanLink-v10.2.3.apk');
    });
  });

  group('platform gating', () {
    test('shareApk is unavailable off-Android without touching the channel',
        () async {
      AppInvite.debugIsSupportedOverride = false;
      var channelTouched = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        channelTouched = true;
        return 'shared';
      });

      final outcome = await AppInvite.shareApk(version: '4.1.0');

      expect(outcome, AppInviteOutcome.unavailable);
      expect(channelTouched, isFalse);
    });

    test('shareDownloadLink is a no-op off-Android', () async {
      AppInvite.debugIsSupportedOverride = false;
      expect(await AppInvite.shareDownloadLink(), isFalse);
    });
  });

  group('method channel contract', () {
    test('shareApk sends the version-stamped file name', () async {
      AppInvite.debugIsSupportedOverride = true;
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return 'shared';
      });

      final outcome = await AppInvite.shareApk(version: '4.1.0');

      expect(outcome, AppInviteOutcome.shared);
      expect(received?.method, 'shareApk');
      expect(received?.arguments, {'fileName': 'LanLink-v4.1.0.apk'});
    });

    test('"split" response maps to needsDownloadLink', () async {
      AppInvite.debugIsSupportedOverride = true;
      messenger.setMockMethodCallHandler(channel, (call) async => 'split');

      expect(
        await AppInvite.shareApk(version: '4.1.0'),
        AppInviteOutcome.needsDownloadLink,
      );
    });

    test('unknown response maps to unavailable', () async {
      AppInvite.debugIsSupportedOverride = true;
      messenger.setMockMethodCallHandler(channel, (call) async => 'weird');

      expect(
        await AppInvite.shareApk(version: '4.1.0'),
        AppInviteOutcome.unavailable,
      );
    });

    test('PlatformException maps to unavailable', () async {
      AppInvite.debugIsSupportedOverride = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'share_failed');
      });

      expect(
        await AppInvite.shareApk(version: '4.1.0'),
        AppInviteOutcome.unavailable,
      );
    });

    test('missing handler maps to unavailable', () async {
      AppInvite.debugIsSupportedOverride = true;
      // No mock handler registered => MissingPluginException.
      expect(
        await AppInvite.shareApk(version: '4.1.0'),
        AppInviteOutcome.unavailable,
      );
    });

    test('shareDownloadLink sends the download URL as text', () async {
      AppInvite.debugIsSupportedOverride = true;
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return true;
      });

      expect(await AppInvite.shareDownloadLink(), isTrue);
      expect(received?.method, 'shareText');
      final args = received?.arguments as Map;
      expect(args['text'], contains(AppInvite.downloadUrl));
    });
  });
}
