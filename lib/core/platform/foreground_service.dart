import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// Test hook for exercising transition/coalescing behaviour on non-Android
  /// hosts. Production code never sets this.
  @visibleForTesting
  static bool debugForceSupported = false;

  bool get isSupported => debugForceSupported || Platform.isAndroid;

  /// Tracks the last value passed to [sync] so we can detect when we need to
  /// actually invoke the platform channel.
  int _lastActiveCount = 0;

  /// Serialises platform mutations. AppState intentionally doesn't await
  /// [sync], so without a tail future a fast start -> finish transition can
  /// let a slow `start` complete *after* `stop`, resurrecting an orphaned
  /// foreground service and its ongoing notification.
  Future<void> _tail = Future.value();

  int _desiredActiveCount = 0;
  bool _drainScheduled = false;
  bool _forceStopPending = false;

  /// Reconcile the foreground-service state with the supplied active
  /// transfer count. Calls are serialised, so a slow native start can never
  /// finish after a newer stop; a non-zero update also refreshes the summary
  /// notification's batch count.
  Future<void> sync(int activeCount) async {
    if (activeCount < 0) activeCount = 0;
    if (!isSupported) {
      _lastActiveCount = activeCount;
      return;
    }
    final wasRunningOrRequested =
        _lastActiveCount > 0 || _desiredActiveCount > 0;
    _desiredActiveCount = activeCount;
    // A 0→0 coalescing result is normally a no-op. It is not a no-op when a
    // start was requested earlier in this turn: native may already have
    // observed that request, so retain a stop barrier even if the drain has
    // not begun yet.
    final forceStop = activeCount == 0 && wasRunningOrRequested;
    _forceStopPending |= forceStop;
    if (!_drainScheduled) {
      _drainScheduled = true;
      _tail = _tail.then((_) => _drain());
    }
    // Let a queued call begin so another synchronous sync() in the same
    // turn can still update [_desiredActiveCount], then wait until every
    // transition known at completion time has drained.
    while (_drainScheduled) {
      final pending = _tail;
      await pending;
      if (identical(pending, _tail) && !_drainScheduled) break;
    }
  }

  Future<void> _drain() async {
    try {
      while (_lastActiveCount != _desiredActiveCount || _forceStopPending) {
        final activeCount = _desiredActiveCount;
        final shouldBeRunning = activeCount > 0;
        final forceStop = !shouldBeRunning && _forceStopPending;
        _forceStopPending = false;
        final wasRunning = _lastActiveCount > 0 || forceStop;
        try {
          if (shouldBeRunning) {
            await _channel.invokeMethod('start', {'activeCount': activeCount});
          } else if (wasRunning) {
            await _channel.invokeMethod('stop');
          }
        } on MissingPluginException {
          // Channel not wired — e.g. running under flutter test on Linux.
        } on PlatformException {
          // The OS denied the start (e.g. background-start rules on Android
          // 12+); the transfer can still proceed in the foreground.
        }
        _lastActiveCount = activeCount;
      }
    } finally {
      _drainScheduled = false;
    }
  }

  @visibleForTesting
  Future<void> debugReset() async {
    _desiredActiveCount = 0;
    _forceStopPending = false;
    await _tail;
    _lastActiveCount = 0;
    _drainScheduled = false;
    _tail = Future.value();
  }
}
