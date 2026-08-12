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

  factory MediaItem.fromMap(Map<dynamic, dynamic> map) => MediaItem(
        id: (map['id'] as num).toInt(),
        name: map['name'] as String,
        path: map['path'] as String,
        size: (map['size'] as num).toInt(),
        isVideo: map['isVideo'] as bool,
        dateModified: (map['dateModified'] as num?)?.toInt() ?? 0,
        bucket: (map['bucket'] as String?) ?? '',
        contentUri: map['contentUri'] as String?,
      );
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
        .map((e) => MediaItem.fromMap(e as Map<dynamic, dynamic>))
        .toList();
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
