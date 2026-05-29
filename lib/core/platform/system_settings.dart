import 'dart:io';

import 'package:flutter/services.dart';

/// Thin Dart-side bridge to the Android system-settings intents wired in
/// [MainActivity.kt]. We use these to bounce the user out to the OS
/// hotspot / Wi-Fi pages from inside the pairing wizard so they don't
/// have to hunt for the toggle themselves.
///
/// All methods return `false` (rather than throwing) when called on
/// platforms or builds where the channel isn't registered, so callers
/// can treat them as best-effort.
class SystemSettings {
  SystemSettings._();

  static const MethodChannel _channel =
      MethodChannel('lanlink/system_settings');

  /// Opens the OS hotspot/tethering settings page so the user can
  /// toggle their hotspot. Android-only — returns false on other
  /// platforms.
  static Future<bool> openHotspotSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openHotspotSettings');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the OS Wi-Fi settings page so the user can join a hotspot
  /// hosted by another device. Android-only.
  static Future<bool> openWifiSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openWifiSettings');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
