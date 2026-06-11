import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Credentials and addressing for a hotspot LanLink is hosting.
@immutable
class HotspotInfo {
  const HotspotInfo({
    required this.ssid,
    required this.password,
    required this.hostIps,
  });

  final String ssid;
  final String password;

  /// Our own IPv4 addresses with the hotspot interface listed first,
  /// so a joining peer can try them in order.
  final List<String> hostIps;

  /// Standard Wi-Fi QR payload understood by the stock camera apps on
  /// both Android and iOS — scanning it offers a one-tap join.
  ///
  /// Format: `WIFI:T:WPA;S:<ssid>;P:<password>;;` with `\;,:"` escaped.
  String toWifiQrString() {
    String esc(String v) => v.replaceAllMapped(
          RegExp(r'([\\;,:"])'),
          (m) => '\\${m[1]}',
        );
    return 'WIFI:T:WPA;S:${esc(ssid)};P:${esc(password)};;';
  }
}

/// Dart bridge to the `lanlink/hotspot` platform channel that wraps
/// Android's `WifiManager.startLocalOnlyHotspot`.
///
/// LocalOnlyHotspot creates a phone-hosted Wi-Fi network with an
/// auto-generated SSID/passphrase and no internet — perfect for moving
/// files when there's no router around. The OS requires a location /
/// nearby-devices runtime permission before it hands the credentials
/// over, hence the explicit permission helpers.
class LocalHotspot {
  LocalHotspot._();

  static const MethodChannel _channel = MethodChannel('lanlink/hotspot');

  /// True when the platform can host a LocalOnlyHotspot (Android 8+).
  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Whether the runtime permission gating hotspot creation is granted.
  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shows the OS permission dialog if needed. Resolves to whether the
  /// permission ended up granted.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Starts (or re-reads) the hotspot. Returns null when the platform
  /// refused — most commonly location services being switched off or
  /// regular tethering already active.
  static Future<HotspotInfo?> start() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('start');
      if (raw == null) return null;
      final ssid = raw['ssid'] as String?;
      final password = raw['password'] as String?;
      final ips = (raw['hostIps'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList();
      if (ssid == null || password == null) return null;
      return HotspotInfo(ssid: ssid, password: password, hostIps: ips);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Tears the hotspot down. Safe to call when none is running.
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // already stopped
    } on MissingPluginException {
      // not available on this build
    }
  }

  /// Whether a LanLink-hosted hotspot is currently up.
  static Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
