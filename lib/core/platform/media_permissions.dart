import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:permission_handler/permission_handler.dart'
    show Permission, PermissionStatus;

/// Outcome of a media-library permission check.
enum MediaAccess {
  /// Reading the media library is allowed (full or user-limited access).
  granted,

  /// The user declined; asking again may show the OS sheet once more.
  denied,

  /// The OS will no longer show the prompt — only the app-settings page
  /// can flip it back on.
  permanentlyDenied,

  /// Not an Android device; the media grid does not apply here.
  unsupported,
}

/// Signature for requesting a batch of permissions. Matches the
/// `permission_handler` list extension so tests can substitute a fake.
typedef MediaPermissionRequester = Future<Map<Permission, PermissionStatus>>
    Function(List<Permission> permissions);

/// Runtime permission gate for the media grid (Android only).
///
/// Strategy — mirrors the platform rules without needing the SDK level
/// in Dart, because `permission_handler` already resolves each group per
/// SDK (a group with no applicable manifest entry reports plain
/// `denied`, never `permanentlyDenied`, and never shows a sheet):
///
/// * Android 13+ (API 33): `Permission.photos/videos/audio` map to the
///   granular `READ_MEDIA_*` permissions declared in the manifest.
///   `Permission.storage` is inert there (`READ_EXTERNAL_STORAGE` has
///   `maxSdkVersion="32"`), so the fallback request is a silent no-op.
/// * Android 12 and below: the granular groups are inert (no
///   `READ_MEDIA_*` before 33), so the first batch resolves to `denied`
///   without a prompt and the legacy `Permission.storage` request is the
///   one that shows the sheet.
class MediaPermissions {
  /// Test-only override so widget tests can exercise the Android flow on
  /// any host platform.
  @visibleForTesting
  static bool debugForceSupported = false;

  /// Test-only stand-in for the permission_handler request call.
  @visibleForTesting
  static MediaPermissionRequester? debugRequester;

  /// Test-only stand-in for the app-settings deep link.
  @visibleForTesting
  static Future<bool> Function()? debugOpenSettings;

  static bool get isSupported => debugForceSupported || Platform.isAndroid;

  static Future<Map<Permission, PermissionStatus>> _platformRequest(
    List<Permission> permissions,
  ) =>
      permissions.request();

  /// Requests media-library access, showing the OS sheet when needed.
  ///
  /// Safe to call on every picker open: already-granted permissions
  /// resolve immediately and permanently-denied ones never re-prompt.
  static Future<MediaAccess> request() async {
    if (!isSupported) return MediaAccess.unsupported;
    final requester = debugRequester ?? _platformRequest;
    try {
      // Granular media permissions first (Android 13+ path).
      final media = await requester(
        [Permission.photos, Permission.videos, Permission.audio],
      );
      if (media.values.any(_allowsReading)) return MediaAccess.granted;

      // Legacy storage permission (Android 12 and below path).
      final legacy = await requester([Permission.storage]);
      if (legacy.values.any(_allowsReading)) return MediaAccess.granted;

      final all = [...media.values, ...legacy.values];
      if (all.any((s) => s.isPermanentlyDenied)) {
        return MediaAccess.permanentlyDenied;
      }
      return MediaAccess.denied;
    } catch (_) {
      // A failing platform call must never masquerade as a grant: the
      // picker shows the retry explainer instead of an empty grid.
      return MediaAccess.denied;
    }
  }

  /// `isLimited` covers Android 14's "allow selected photos" answer —
  /// MediaStore then returns the user's selection, which we can show.
  static bool _allowsReading(PermissionStatus status) =>
      status.isGranted || status.isLimited;

  /// Deep-links to the app's system settings page so the user can flip a
  /// permanently-denied permission back on.
  static Future<bool> openSettings() =>
      (debugOpenSettings ?? ph.openAppSettings)();
}
