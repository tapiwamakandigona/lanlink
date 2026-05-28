import 'dart:io';

import 'package:flutter/services.dart';

/// Thin bridge to the Android foreground service that keeps the OS from
/// killing LanLink while a transfer is in flight.
///
/// On non-Android platforms every method is a no-op so call sites don't
/// need their own platform guards. On Android, the service is started when
/// the first transfer becomes active and stopped when no transfers remain.
class TransferForegroundService {
  TransferForegroundService._();
  static final TransferForegroundService instance =
      TransferForegroundService._();

  static const _channel = MethodChannel('lanlink/foreground_service');

  bool get isSupported => Platform.isAndroid;

  /// Tracks the last value passed to [sync] so we can detect when we need to
  /// actually invoke the platform channel.
  int _lastActiveCount = 0;

  /// Reconcile the foreground-service state with the supplied active
  /// transfer count. Calls are idempotent; the platform channel is only
  /// invoked when the count crosses the 0/non-zero boundary.
  Future<void> sync(int activeCount) async {
    if (!isSupported) {
      _lastActiveCount = activeCount;
      return;
    }
    final shouldBeRunning = activeCount > 0;
    final wasRunning = _lastActiveCount > 0;
    _lastActiveCount = activeCount;
    try {
      if (shouldBeRunning) {
        await _channel.invokeMethod('start', {'activeCount': activeCount});
      } else if (wasRunning) {
        await _channel.invokeMethod('stop');
      }
    } on MissingPluginException {
      // Channel not wired — e.g. running under flutter test on Linux.
    } on PlatformException {
      // The OS denied the start (e.g. exact-alarm rules on Android 12+);
      // the transfer can still proceed in the foreground, so swallow the
      // error rather than failing the user's send.
    }
  }
}
