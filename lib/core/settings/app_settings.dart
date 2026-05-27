import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../connectivity/connectivity_mode.dart';
import '../protocol/constants.dart';

/// Persistent user-facing settings.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static const _aliasKey = 'lanlink_alias';
  static const _portKey = 'lanlink_port';
  static const _saveDirKey = 'lanlink_save_dir';
  static const _quickSaveKey = 'lanlink_quick_save';
  static const _trustedKey = 'lanlink_trusted_fingerprints';
  static const _connectivityModeKey = 'lanlink_connectivity_mode';
  static const _hotspotRoleKey = 'lanlink_hotspot_role';
  static const _autoUpdateKey = 'lanlink_auto_update_check';

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  String get alias => _prefs.getString(_aliasKey) ?? '';
  int get port => _prefs.getInt(_portKey) ?? LanLinkProtocol.defaultPort;
  String? get saveDir => _prefs.getString(_saveDirKey);
  bool get quickSave => _prefs.getBool(_quickSaveKey) ?? false;
  ConnectivityMode get connectivityMode {
    final name = _prefs.getString(_connectivityModeKey);
    return ConnectivityMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ConnectivityMode.lan,
    );
  }

  HotspotRole get hotspotRole {
    final name = _prefs.getString(_hotspotRoleKey);
    return HotspotRole.values.firstWhere(
      (role) => role.name == name,
      orElse: () => HotspotRole.auto,
    );
  }

  bool get autoUpdateCheck => _prefs.getBool(_autoUpdateKey) ?? true;

  Set<String> get trustedFingerprints {
    final raw = _prefs.getString(_trustedKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (json.decode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> setAlias(String value) async {
    await _prefs.setString(_aliasKey, value);
    notifyListeners();
  }

  Future<void> setPort(int value) async {
    await _prefs.setInt(_portKey, value);
    notifyListeners();
  }

  Future<void> setSaveDir(String? value) async {
    if (value == null) {
      await _prefs.remove(_saveDirKey);
    } else {
      await _prefs.setString(_saveDirKey, value);
    }
    notifyListeners();
  }

  Future<void> setQuickSave(bool value) async {
    await _prefs.setBool(_quickSaveKey, value);
    notifyListeners();
  }

  Future<void> setConnectivityMode(ConnectivityMode value) async {
    await _prefs.setString(_connectivityModeKey, value.name);
    notifyListeners();
  }

  Future<void> setHotspotRole(HotspotRole value) async {
    await _prefs.setString(_hotspotRoleKey, value.name);
    notifyListeners();
  }

  Future<void> setAutoUpdateCheck(bool value) async {
    await _prefs.setBool(_autoUpdateKey, value);
    notifyListeners();
  }

  Future<void> trust(String fingerprint) async {
    final set = trustedFingerprints..add(fingerprint);
    await _prefs.setString(_trustedKey, json.encode(set.toList()));
    notifyListeners();
  }

  Future<void> untrust(String fingerprint) async {
    final set = trustedFingerprints..remove(fingerprint);
    await _prefs.setString(_trustedKey, json.encode(set.toList()));
    notifyListeners();
  }
}
