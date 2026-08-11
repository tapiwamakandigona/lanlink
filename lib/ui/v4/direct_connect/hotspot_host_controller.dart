import 'package:flutter/foundation.dart';

import '../../../core/platform/local_hotspot.dart';

/// Where the Direct link host flow currently is. Mirrors the v3.5 page's
/// phase machine (`host_hotspot_page.dart`) but lives outside the widget
/// tree so the receive page stays a thin view.
enum HotspotHostPhase {
  /// Direct link not selected / hotspot not running.
  idle,

  /// Checking platform support + permission.
  checking,

  /// The OS permission gating LocalOnlyHotspot is missing; the UI should
  /// offer a single "Allow and continue" action.
  needsPermission,

  /// `startLocalOnlyHotspot` is in flight.
  starting,

  /// Hotspot is up; [info] carries SSID / password / host IPs.
  running,

  /// The platform refused (unsupported, permission declined, location off,
  /// tethering already active…); [error] has a human explanation.
  failed,
}

/// Drives the host side of Direct Connect: start the in-app
/// LocalOnlyHotspot, expose its credentials for the QR payload, and
/// guarantee teardown when receive stops or the page goes away.
///
/// Platform calls are injectable so tests never touch method channels.
class HotspotHostController extends ChangeNotifier {
  HotspotHostController({
    Future<bool> Function()? isSupported,
    Future<bool> Function()? hasPermission,
    Future<bool> Function()? requestPermission,
    Future<HotspotInfo?> Function()? start,
    Future<void> Function()? stop,
  })  : _isSupported = isSupported ?? LocalHotspot.isSupported,
        _hasPermission = hasPermission ?? LocalHotspot.hasPermission,
        _requestPermission =
            requestPermission ?? LocalHotspot.requestPermission,
        _start = start ?? LocalHotspot.start,
        _stop = stop ?? LocalHotspot.stop;

  final Future<bool> Function() _isSupported;
  final Future<bool> Function() _hasPermission;
  final Future<bool> Function() _requestPermission;
  final Future<HotspotInfo?> Function() _start;
  final Future<void> Function() _stop;

  HotspotHostPhase _phase = HotspotHostPhase.idle;
  HotspotInfo? _info;
  String? _error;
  bool _disposed = false;

  HotspotHostPhase get phase => _phase;
  HotspotInfo? get info => _info;
  String? get error => _error;
  bool get isRunning => _phase == HotspotHostPhase.running && _info != null;

  /// Entry point when the user flips to "No shared Wi-Fi": support check →
  /// permission check → start. Safe to call again from `failed`.
  Future<void> enable() async {
    if (_phase == HotspotHostPhase.running ||
        _phase == HotspotHostPhase.starting ||
        _phase == HotspotHostPhase.checking) {
      return;
    }
    _set(HotspotHostPhase.checking);
    final supported = await _isSupported();
    if (_disposed) return;
    if (!supported) {
      _fail(_unsupportedMessage());
      return;
    }
    // Windows has no runtime permission gating hotspots — go straight to
    // start instead of dead-ending in a permission phase that can never
    // show a dialog.
    if (defaultTargetPlatform != TargetPlatform.windows) {
      final granted = await _hasPermission();
      if (_disposed) return;
      if (!granted) {
        _set(HotspotHostPhase.needsPermission);
        return;
      }
    }
    await _startHotspot();
  }

  /// Why "No shared Wi-Fi" can't run here, in words that fit the device
  /// the user is actually looking at.
  static String _unsupportedMessage() {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return "This PC can't start a hotspot right now. It may not have "
          'a Wi-Fi adapter, or the adapter may be turned off.';
    }
    return "This device can't create a hotspot from an app "
        '(needs Android 8 or newer).';
  }

  /// Runs the OS permission dialog, then starts the hotspot on grant.
  Future<void> grantPermission() async {
    final ok = await _requestPermission();
    if (_disposed) return;
    if (!ok) {
      _fail('Permission was declined. LanLink needs it only to create '
          'the direct link — nothing is tracked.');
      return;
    }
    await _startHotspot();
  }

  Future<void> _startHotspot() async {
    _set(HotspotHostPhase.starting);
    final info = await _start();
    if (_disposed) {
      // The page died while the platform was still starting up — don't
      // leave an orphaned reservation behind.
      if (info != null) await _stop();
      return;
    }
    if (info == null) {
      _fail(defaultTargetPlatform == TargetPlatform.windows
          ? 'Could not start the direct link. Check that Wi-Fi is turned '
              'on, then try again.'
          : 'Could not start the direct link. Check that Location is on '
              'and that regular hotspot/tethering is off, then try again.');
      return;
    }
    _info = info;
    _error = null;
    _set(HotspotHostPhase.running);
  }

  /// Tears the hotspot down and returns to idle. Safe to call anytime.
  Future<void> disable() async {
    final wasIdle = _phase == HotspotHostPhase.idle;
    _info = null;
    _error = null;
    if (!_disposed) {
      _set(HotspotHostPhase.idle);
    } else {
      _phase = HotspotHostPhase.idle;
    }
    if (!wasIdle) await _stop();
  }

  void _fail(String message) {
    _error = message;
    _info = null;
    _set(HotspotHostPhase.failed);
  }

  void _set(HotspotHostPhase phase) {
    _phase = phase;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    // Fire-and-forget: the reservation must never outlive its page.
    if (_phase != HotspotHostPhase.idle) {
      _info = null;
      _phase = HotspotHostPhase.idle;
      // ignore: discarded_futures
      _stop();
    }
    _disposed = true;
    super.dispose();
  }
}
