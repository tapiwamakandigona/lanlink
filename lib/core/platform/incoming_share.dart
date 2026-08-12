import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/file_info.dart';

/// Files that another Android app handed us via "Share to LanLink".
///
/// The native side keeps the URI permission alive while this activity
/// exists, and the sender streams directly from [FileInfo.contentUri].
/// Avoiding an eager cache copy means selecting a multi-gigabyte video
/// opens LanLink immediately and does not require double the free space.
class IncomingShare {
  IncomingShare._();

  static const MethodChannel _channel = MethodChannel('lanlink/incoming_share');

  static void Function()? _listener;

  /// Test-only override so the Android bridge can be exercised on the host.
  @visibleForTesting
  static bool debugForceSupported = false;

  static bool get isSupported => debugForceSupported || Platform.isAndroid;

  /// Drains any pending shares that the OS handed our [MainActivity]
  /// while we were closed or in the background. Returns empty on
  /// non-Android platforms or when the bridge isn't loaded.
  static Future<List<FileInfo>> consume() async {
    if (!isSupported) return const [];
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
  /// app is already running. Pair with [consume] inside the callback. Pass
  /// null when the owning page is disposed so the static platform handler
  /// cannot retain/call a dead State object.
  static void onShareReceived(void Function()? callback) {
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
    final contentUri = map['contentUri']?.toString();
    final path = map['path']?.toString();
    final name = map['fileName']?.toString();
    final sizeRaw = map['size'];
    if (sizeRaw != null &&
        (sizeRaw is! num ||
            !sizeRaw.isFinite ||
            sizeRaw != sizeRaw.truncateToDouble())) {
      return null;
    }
    final size = sizeRaw is num ? sizeRaw.toInt() : -1;
    final hasContentUri = contentUri != null && contentUri.isNotEmpty;
    final hasPath = path != null && path.isNotEmpty;
    if ((!hasContentUri && !hasPath) ||
        name == null ||
        name.isEmpty ||
        size < -1) {
      return null;
    }
    final actualSize =
        size >= 0 ? size : (hasPath ? await _safeFileSize(path) : 0);
    return FileInfo(
      id: 'incoming-${DateTime.now().microsecondsSinceEpoch}-$name',
      fileName: name,
      size: actualSize,
      fileType: fileTypeForName(name),
      localPath: hasPath ? path : null,
      contentUri: hasContentUri ? contentUri : null,
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
