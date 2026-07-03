import 'dart:io';

import 'package:flutter/services.dart';

import '../models/file_info.dart';

/// Files that another Android app handed us via "Share to LanLink".
/// Each file has already been copied into our cache by the platform
/// side, so [localPath] is owned by us and safe to read until the
/// transfer is done.
class IncomingShare {
  IncomingShare._();

  static const MethodChannel _channel = MethodChannel('lanlink/incoming_share');

  static void Function()? _listener;

  /// Drains any pending shares that the OS handed our [MainActivity]
  /// while we were closed or in the background. Returns empty on
  /// non-Android platforms or when the bridge isn't loaded.
  static Future<List<FileInfo>> consume() async {
    if (!Platform.isAndroid) return const [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('consume');
      if (result == null) return const [];
      final decoded = await Future.wait(result.map(_decode));
      return decoded.whereType<FileInfo>().toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Registers a callback that fires when a new share arrives while the
  /// app is already running. Pair with [consume] inside the callback.
  static void onShareReceived(void Function() callback) {
    _listener = callback;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShareReceived') {
        _listener?.call();
      }
      return null;
    });
  }

  static Future<FileInfo?> _decode(dynamic raw) async {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final path = map['path']?.toString();
    final name = map['fileName']?.toString();
    final size = (map['size'] as num?)?.toInt() ?? -1;
    if (path == null || name == null || path.isEmpty || name.isEmpty) {
      return null;
    }
    final actualSize = size >= 0 ? size : await _safeFileSize(path);
    return FileInfo(
      id: 'incoming-${DateTime.now().microsecondsSinceEpoch}-$name',
      fileName: name,
      size: actualSize,
      fileType: fileTypeForName(name),
      localPath: path,
    );
  }

  /// Async stat: this runs on the UI isolate during HomePage init, so the
  /// one file-system touch here must never block frame production.
  static Future<int> _safeFileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }
}
