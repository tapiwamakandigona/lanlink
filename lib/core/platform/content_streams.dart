import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One file picked via the system document picker (Storage Access
/// Framework). Carries the content URI — no bytes are copied anywhere.
class PickedContent {
  const PickedContent({
    required this.uri,
    required this.name,
    required this.size,
  });

  /// `content://` URI the sender streams from.
  final String uri;
  final String name;
  final int size;

  factory PickedContent.fromMap(Map<dynamic, dynamic> map) => PickedContent(
        uri: map['uri'] as String,
        name: map['name'] as String,
        size: (map['size'] as num).toInt(),
      );
}

/// Dart bridge to the `lanlink/saf` platform channel (Android only).
///
/// Replaces the file_picker plugin on Android for the "All files" flow:
/// file_picker copies every picked file into the app cache before returning
/// a path — for a multi-GB video that is minutes of silent wait plus a
/// duplicate copy on disk. This picker returns content URIs immediately and
/// [openRead] streams bytes straight from the source provider.
class ContentStreams {
  static const _channel = MethodChannel('lanlink/saf');

  /// Bytes fetched per platform-channel round trip. Large enough that the
  /// per-call overhead vanishes next to network I/O, small enough to keep
  /// only one chunk buffered.
  static const int chunkSize = 512 * 1024;

  /// Test-only override so widget tests can exercise the Android flow on
  /// any host platform.
  @visibleForTesting
  static bool debugForceSupported = false;

  static bool get isSupported => debugForceSupported || Platform.isAndroid;

  /// Opens the system document picker (multi-select, any type). Returns an
  /// empty list on cancel. Throws on platform errors so callers can fall
  /// back to file_picker.
  static Future<List<PickedContent>> pickFiles() async {
    final raw = await _channel.invokeListMethod<dynamic>('pickFiles');
    if (raw == null) return const [];
    return raw
        .map((e) => PickedContent.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  /// Streams the content of [uri] starting at byte [start].
  ///
  /// The native side keeps an open InputStream per handle; chunks are
  /// pulled sequentially, so backpressure from a slow consumer (the HTTP
  /// upload) naturally paces the reads. The handle is always closed — on
  /// EOF, error, and stream cancellation alike.
  static Stream<Uint8List> openRead(String uri, {int start = 0}) async* {
    final id = await _channel.invokeMethod<int>('openStream', {
      'uri': uri,
      'offset': start,
    });
    if (id == null) {
      throw StateError('Could not open content stream for $uri');
    }
    try {
      while (true) {
        final chunk = await _channel.invokeMethod<Uint8List>('readChunk', {
          'id': id,
          'max': chunkSize,
        });
        if (chunk == null || chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      unawaited(
        _channel.invokeMethod<void>('closeStream', {'id': id}).catchError(
          (_) {},
        ),
      );
    }
  }
}
