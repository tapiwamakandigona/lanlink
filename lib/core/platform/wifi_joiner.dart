import 'dart:io';

import 'package:flutter/services.dart';

/// Dart bridge to the `lanlink/wifi` platform channel.
///
/// Joins a receiver-hosted hotspot programmatically using Android's
/// `WifiNetworkSpecifier` (API 29+) so a single QR scan both joins the
/// network and connects — no trip to Wi-Fi settings. The platform side
/// binds the process to the new network so our sockets route over it.
class WifiJoiner {
  static const _channel = MethodChannel('lanlink/wifi');

  static bool get isPlatformSupported => Platform.isAndroid;

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

  /// Joins the hotspot and binds the process to it. Resolves true once
  /// the network is available, false on failure/timeout (~30 s).
  static Future<bool> join(String ssid, String password) async {
    if (!isPlatformSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'join',
            {'ssid': ssid, 'password': password},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Releases the network request and unbinds the process. Safe to call
  /// even when nothing was joined.
  static Future<void> leave() async {
    if (!isPlatformSupported) return;
    try {
      await _channel.invokeMethod<void>('leave');
    } catch (_) {
      // Best effort.
    }
  }
}
