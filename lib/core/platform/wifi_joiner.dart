import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Outcome of a programmatic hotspot join, mirroring the machine-readable
/// reasons the platform side reports so the UI can drive the tiered
/// fallback (retry text, "Add network" panel, manual Wi-Fi settings).
enum WifiJoinResult {
  /// Network available and the process is bound to it.
  connected,

  /// The system dialog was declined, or no scan match was found (after the
  /// platform side's one silent retry).
  declinedOrUnavailable,

  /// Nothing settled within the platform-side timeout (~60 s).
  timeout,

  /// Programmatic joins need Android 10+; other platforms/versions land
  /// here immediately.
  unsupported,

  /// The network request itself failed (threw) on the platform side.
  error;

  /// True only for a successful, bound join.
  bool get joined => this == WifiJoinResult.connected;
}

/// Dart bridge to the `lanlink/wifi` platform channel.
///
/// Joins a receiver-hosted hotspot programmatically using Android's
/// `WifiNetworkSpecifier` (API 29+) so a single QR scan both joins the
/// network and connects — no trip to Wi-Fi settings. The platform side
/// binds the process to the new network so our sockets route over it, and
/// keeps the network request registered until [leave] (releasing it would
/// tear the local-only network down).
class WifiJoiner {
  static const _channel = MethodChannel('lanlink/wifi');

  static bool _handlerInstalled = false;
  static void Function()? _onNetworkLost;

  /// Test hook: forces [isAddNetworksSupported] (platform channels don't
  /// exist under `flutter test`).
  static bool? debugAddNetworksSupportedOverride;

  /// Test hook: replaces the [fallbackAddNetwork] platform call.
  static Future<bool> Function(String ssid, String password)?
      debugFallbackAddNetwork;

  /// Test hook: replaces the [leave] platform call, so tests can pin the
  /// contract that Tier-2/3 (device-level) joins release nothing.
  static Future<void> Function()? debugLeave;

  /// Test hook: forces [isPlatformSupported] (there is no Android under
  /// `flutter test`, but the channel itself can be mocked).
  static bool? debugPlatformSupportedOverride;

  /// Dart-side guard on the platform `join` reply (see [join]). Mutable so
  /// tests can shrink it instead of waiting 90 real seconds.
  static Duration joinReplyTimeout = const Duration(seconds: 90);

  static bool get isPlatformSupported =>
      debugPlatformSupportedOverride ?? Platform.isAndroid;

  /// Registers (or clears, with null) the callback fired when a joined
  /// hotspot network drops (`onLost` on the platform side, which also
  /// unbinds the process). Only one listener at a time — the surface that
  /// currently owns the join installs its own.
  static void setOnNetworkLost(void Function()? handler) {
    _onNetworkLost = handler;
    if (_handlerInstalled || !isPlatformSupported) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNetworkLost') _onNetworkLost?.call();
      return null;
    });
  }

  /// True when this device can join a hotspot programmatically
  /// (Android 10+). Other platforms / older Androids return false and the
  /// UI falls back to "join the hotspot in Wi-Fi settings" instructions.
  static Future<bool> isSupported() async {
    if (!isPlatformSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True when the system "Add networks" save panel (Tier-2 join fallback)
  /// is available — Android 11+ (API 30).
  static Future<bool> isAddNetworksSupported() async {
    final override = debugAddNetworksSupportedOverride;
    if (override != null) return override;
    if (!isPlatformSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAddNetworksSupported') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Joins the hotspot and binds the process to it. Resolves with the
  /// machine-readable outcome; the platform side waits up to ~60 s (the OS
  /// picker scans every ~10 s and first-time joins need a user tap in the
  /// system dialog, so shorter app timers race the dialog and lose).
  ///
  /// Safety net: like [fallbackAddNetwork], the platform reply can get lost
  /// (activity recreation, OEM lifecycle quirks) — without a Dart-side
  /// guard that wedges the Send page spinner forever. The platform side
  /// waits ~60 s plus one silent retry, so 90 s gives it headroom while
  /// still resolving to [WifiJoinResult.timeout] eventually.
  static Future<WifiJoinResult> join(String ssid, String password) async {
    if (!isPlatformSupported) return WifiJoinResult.unsupported;
    try {
      final reason = await _channel.invokeMethod<String>(
        'join',
        {'ssid': ssid, 'password': password},
      ).timeout(joinReplyTimeout);
      switch (reason) {
        case 'connected':
          return WifiJoinResult.connected;
        case 'declined_or_unavailable':
          return WifiJoinResult.declinedOrUnavailable;
        case 'timeout':
          return WifiJoinResult.timeout;
        case 'unsupported':
          return WifiJoinResult.unsupported;
        default:
          return WifiJoinResult.error;
      }
    } on TimeoutException {
      return WifiJoinResult.timeout;
    } catch (_) {
      return WifiJoinResult.error;
    }
  }

  /// Tier-2 join fallback: opens the system "Add networks" panel
  /// pre-filled with the hotspot credentials (API 30+). Resolves true when
  /// the user saved the network. The network is joined at device level —
  /// there is no process binding to release afterwards.
  ///
  /// Safety net: the platform reply can get lost if the activity is
  /// recreated behind the Settings panel (process death, rare OEM
  /// lifecycle quirks) — the call then times out to false instead of
  /// wedging the fallback flow with a spinner forever.
  static Future<bool> fallbackAddNetwork(String ssid, String password) async {
    final override = debugFallbackAddNetwork;
    if (override != null) return override(ssid, password);
    if (!isPlatformSupported) return false;
    try {
      final saved = await _channel.invokeMethod<bool>(
        'fallbackAddNetwork',
        {'ssid': ssid, 'password': password},
      ).timeout(const Duration(minutes: 3));
      return saved ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Releases the network request and unbinds the process. Safe to call
  /// even when nothing was joined. This is the ONLY place a successful
  /// join's request gets unregistered (session end / disconnect).
  static Future<void> leave() async {
    final override = debugLeave;
    if (override != null) return override();
    if (!isPlatformSupported) return;
    try {
      await _channel.invokeMethod<void>('leave');
    } catch (_) {
      // Best effort.
    }
  }
}
