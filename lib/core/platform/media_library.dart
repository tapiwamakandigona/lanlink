import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'media_permissions.dart';

/// One photo or video from the device's media library (Android MediaStore).
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.isVideo,
    required this.dateModified,
    required this.bucket,
    this.contentUri,
  });

  /// MediaStore row id — used to fetch thumbnails.
  final int id;
  final String name;

  /// Legacy absolute path, when one exists. Modern Android media is streamed
  /// from [contentUri] instead so scoped storage cannot block the send.
  final String path;
  final int size;
  final bool isVideo;

  /// Seconds since epoch; newest items sort first.
  final int dateModified;

  /// Album / folder display name ("Camera", "Screenshots", …).
  final String bucket;

  /// Stable MediaStore URI. Prefer this over [path] for reads: direct paths
  /// are not accessible under Android 10 scoped storage.
  final String? contentUri;

  static MediaItem? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    int? exactNonNegative(Object? value) {
      if (value is! num ||
          !value.isFinite ||
          value != value.truncateToDouble() ||
          value < 0) {
        return null;
      }
      return value.toInt();
    }

    final id = exactNonNegative(raw['id']);
    final size = exactNonNegative(raw['size']);
    final name = raw['name'];
    final path = raw['path'];
    final contentUri = raw['contentUri'];
    if (id == null ||
        size == null ||
        name is! String ||
        name.isEmpty ||
        path is! String ||
        raw['isVideo'] is! bool ||
        (path.isEmpty &&
            (contentUri is! String || contentUri.trim().isEmpty))) {
      return null;
    }
    return MediaItem(
      id: id,
      name: name,
      path: path,
      size: size,
      isVideo: raw['isVideo'] as bool,
      dateModified: exactNonNegative(raw['dateModified']) ?? 0,
      bucket: raw['bucket'] is String ? raw['bucket'] as String : '',
      contentUri:
          contentUri is String && contentUri.isNotEmpty ? contentUri : null,
    );
  }
}

/// Dart bridge to the `lanlink/media` platform channel (Android only).
///
/// Desktop and iOS callers get empty results; the UI hides the photo
/// picker entry there and falls back to the system file picker.
class MediaLibrary {
  static const _channel = MethodChannel('lanlink/media');

  /// Test-only override so widget tests and goldens can render the
  /// Android experience on any host platform.
  @visibleForTesting
  static bool debugForceSupported = false;

  static bool get isSupported => debugForceSupported || Platform.isAndroid;

  /// Asks for whichever runtime permission the OS needs to read the media
  /// library (READ_MEDIA_* on Android 13+, storage before). Callers that
  /// need the denied/permanently-denied distinction should use
  /// [MediaPermissions.request] directly.
  static Future<bool> ensurePermission() async =>
      await MediaPermissions.request() == MediaAccess.granted;

  /// Every photo and video on the device, newest first.
  static Future<List<MediaItem>> listMedia() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<dynamic>('listMedia');
    if (raw == null) return const [];
    return raw
        .map(MediaItem.tryFromMap)
        .whereType<MediaItem>()
        .toList(growable: false);
  }

  /// Small JPEG thumbnail for a media item, or null when unavailable.
  static Future<Uint8List?> thumbnail(int id, {required bool isVideo}) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', {
        'id': id,
        'isVideo': isVideo,
      });
    } catch (_) {
      return null;
    }
  }
}
