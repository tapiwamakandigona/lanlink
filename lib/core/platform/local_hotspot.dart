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
/// Android's `WifiManager.startLocalOnlyHotspot` and, on Windows, the
/// Mobile Hotspot (`NetworkOperatorTetheringManager`) API.
///
/// The hosted network is a device-local Wi-Fi network with an
/// SSID/passphrase and no internet — perfect for moving files when
/// there's no router around. Android requires a location /
/// nearby-devices runtime permission before it hands the credentials
/// over, hence the explicit permission helpers; Windows has no runtime
/// permission concept, so those short-circuit to true there.
class LocalHotspot {
  LocalHotspot._();

  static const MethodChannel _channel = MethodChannel('lanlink/hotspot');

  /// Platforms where an in-app hotspot host exists (Android 8+, Windows).
  static bool get _platformHasHost => Platform.isAndroid || Platform.isWindows;

  /// True when the platform can host an in-app hotspot.
  static Future<bool> isSupported() async {
    if (!_platformHasHost) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Whether the runtime permission gating hotspot creation is granted.
  /// Windows has no such permission — always granted there.
  static Future<bool> hasPermission() async {
    if (Platform.isWindows) return true;
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
  /// permission ended up granted. A no-op success on Windows.
  static Future<bool> requestPermission() async {
    if (Platform.isWindows) return true;
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
    if (!_platformHasHost) return null;
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
    if (!_platformHasHost) return;
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
    if (!_platformHasHost) return false;
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
