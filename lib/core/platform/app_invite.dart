import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Outcome of asking the platform to share our own APK.
enum AppInviteOutcome {
  /// The system share sheet opened with the APK attached.
  shared,

  /// This install is split into multiple APKs (Play-style delivery), so
  /// sharing the base split would produce a broken install. Offer the
  /// universal-download link instead.
  needsDownloadLink,

  /// Sharing is not available (wrong platform, missing handler, or the
  /// platform side failed).
  unavailable,
}

/// Dart bridge to the `lanlink/app_invite` platform channel.
///
/// Android-only "Invite a friend" flow: the platform side resolves this
/// app's own APK (`applicationInfo.sourceDir`), copies it into the cache
/// directory under a friendly name, exposes it through the existing
/// FileProvider, and fires `ACTION_SEND` with the APK mime type so the
/// user can pick Bluetooth / Quick Share in the system sheet.
class AppInvite {
  AppInvite._();

  static const MethodChannel _channel = MethodChannel('lanlink/app_invite');

  /// Where to get LanLink when the APK can't be shared directly.
  static const String downloadUrl = 'https://tapiwa.me/lanlink/downloads';

  /// Test hook: overrides the platform check so widget/unit tests can
  /// exercise both branches without running on Android.
  @visibleForTesting
  static bool? debugIsSupportedOverride;

  /// True only on Android — sharing our own APK makes no sense anywhere
  /// else (iOS forbids it outright; desktop installs aren't APKs).
  static bool get isSupported {
    final override = debugIsSupportedOverride;
    if (override != null) return override;
    return Platform.isAndroid;
  }

  /// Friendly file name the copied APK is exposed under, e.g.
  /// `LanLink-v4.1.0.apk`. Kept version-stamped so the receiver can tell
  /// at a glance what they were sent.
  static String apkFileName(String version) => 'LanLink-v$version.apk';

  /// Opens the system share sheet with our own APK attached.
  ///
  /// [version] stamps the shared file name; pass the running app's
  /// version string (e.g. `4.1.0`).
  static Future<AppInviteOutcome> shareApk({required String version}) async {
    if (!isSupported) return AppInviteOutcome.unavailable;
    try {
      final status = await _channel.invokeMethod<String>('shareApk', {
        'fileName': apkFileName(version),
      });
      switch (status) {
        case 'shared':
          return AppInviteOutcome.shared;
        case 'split':
          return AppInviteOutcome.needsDownloadLink;
        default:
          return AppInviteOutcome.unavailable;
      }
    } on MissingPluginException {
      return AppInviteOutcome.unavailable;
    } on PlatformException {
      return AppInviteOutcome.unavailable;
    }
  }

  /// Shares [text] via a plain-text `ACTION_SEND` — used to pass the
  /// download link along when the APK itself can't be attached.
  static Future<bool> shareDownloadLink() async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('shareText', {
        'text': 'Get LanLink — fast local file sharing: $downloadUrl',
      });
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
