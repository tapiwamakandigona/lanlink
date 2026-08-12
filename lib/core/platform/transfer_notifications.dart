import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/session.dart';
import '../util/format.dart';

/// Bridge to the Android notification helper. On other platforms every
/// method is a no-op so call sites don't need their own `if (Platform.…)`.
///
/// Each [TransferSession] gets its own notification id (stable hash of the
/// session id). While the transfer is in progress we post an ongoing
/// notification with a progress bar and "X / Y MB" subtitle, then swap it
/// out for an autocancellable terminal notification ("Saved 3 files to
/// Downloads/LanLink") once the session finishes.
class TransferNotifications {
  TransferNotifications._();
  static final TransferNotifications instance = TransferNotifications._();

  static const _channel = MethodChannel('lanlink/notifications');
  Future<void>? _permissionRequest;

  /// Test hook: lets widget tests exercise the notification text/argument
  /// building on non-Android hosts by forcing [isSupported] true (the
  /// channel itself is mocked in tests). Production code never sets this.
  @visibleForTesting
  static bool debugForceSupported = false;

  /// Lightweight runtime check — saves Dart from issuing channel calls on
  /// non-Android platforms that don't register the channel.
  bool get isSupported => debugForceSupported || Platform.isAndroid;

  /// Asks for POST_NOTIFICATIONS once per process. Safe to call repeatedly:
  /// the first call owns the system dialog and every later call awaits the
  /// same in-flight future (a bool guard here would let a second session
  /// post pre-grant while the dialog is still up). Failure (denial, missing
  /// API on older Android) doesn't throw — the notification methods just
  /// become silent.
  Future<void> ensurePermission() {
    if (!isSupported) return Future.value();
    return _permissionRequest ??= () async {
      try {
        await Permission.notification.request();
      } catch (_) {
        // ignore — POST_NOTIFICATIONS is only required on Android 13+ and
        // permission_handler may throw on older OS where the call is moot.
      }
    }();
  }

  Future<void> showProgress(TransferSession session) async {
    if (!isSupported) return;
    final notifId = _idFor(session);
    final isReceive = session.direction == TransferDirection.receive;
    final verb = isReceive ? 'Receiving from' : 'Sending to';
    final peer = session.peer.alias.isEmpty ? 'a device' : session.peer.alias;
    final total = session.totalBytes;
    final transferred = session.transferredBytes;
    final indeterminate =
        session.status == TransferStatus.awaitingAccept || total <= 0;
    final pct = total > 0 ? ((transferred / total) * 100).round() : 0;
    final subtitle = total > 0
        ? '${formatBytes(transferred)} / ${formatBytes(total)} ($pct%)'
        : (session.status == TransferStatus.awaitingAccept
            ? 'Waiting for confirmation'
            : 'Preparing…');
    try {
      await _channel.invokeMethod('showProgress', {
        'id': notifId,
        'title': '$verb $peer',
        'text': subtitle,
        'progress': pct,
        'max': 100,
        'indeterminate': indeterminate,
      });
    } on MissingPluginException {
      // Channel not wired — desktop build, or older snapshot.
    } on PlatformException catch (e) {
      // A notification failure must never take down a transfer.
      if (kDebugMode) debugPrint('[notif] showProgress failed: $e');
    }
  }

  Future<void> showFinal(TransferSession session) async {
    if (!isSupported) return;
    final notifId = _idFor(session);
    final isReceive = session.direction == TransferDirection.receive;
    final fileCount = session.files.length;
    final fileLabel = fileCount == 1 ? 'file' : 'files';
    final peer = session.peer.alias.isEmpty ? 'a device' : session.peer.alias;
    final saved = session.files.values
        .map((f) => f.savedPath)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
    String title;
    String text;
    bool success;
    switch (session.status) {
      case TransferStatus.completed:
        success = true;
        if (isReceive) {
          title = 'Received $fileCount $fileLabel';
          text = saved.isNotEmpty
              ? 'Saved to ${saved.first.replaceAll(RegExp(r'/[^/]+$'), '')}'
              : 'From $peer';
        } else {
          title = 'Sent $fileCount $fileLabel';
          text = 'To $peer';
        }
        break;
      case TransferStatus.failed:
        success = false;
        title = isReceive ? 'Receive failed' : 'Send failed';
        text = isReceive ? 'From $peer' : 'To $peer';
        break;
      case TransferStatus.cancelled:
        success = false;
        title = isReceive ? 'Receive cancelled' : 'Send cancelled';
        text = isReceive ? 'From $peer' : 'To $peer';
        break;
      default:
        return;
    }
    try {
      await _channel.invokeMethod('showFinal', {
        'id': notifId,
        'title': title,
        'text': text,
        'success': success,
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[notif] showFinal failed: $e');
    }
  }

  Future<void> cancel(TransferSession session) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('cancel', {'id': _idFor(session)});
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[notif] cancel failed: $e');
    }
  }

  /// Hash a session id into a stable, positive 31-bit integer notification id.
  /// Different sessions hashing to the same id is extremely unlikely (~1 in
  /// 2 billion) and only means two in-flight notifications would collide.
  int _idFor(TransferSession session) {
    var hash = 0;
    for (final c in session.sessionId.codeUnits) {
      hash = ((hash << 5) - hash + c) & 0x7fffffff;
    }
    return hash;
  }
}
