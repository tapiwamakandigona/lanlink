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
  static const _skippedUpdateKey = 'lanlink_skipped_update_version';
  static const _peerNicknamesKey = 'lanlink_peer_nicknames';

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

  /// The release tag the user explicitly dismissed via "Skip this version".
  /// The update banner won't reappear for this tag, but the user can still
  /// pull up release notes by tapping "Check for updates" in Settings.
  /// Cleared automatically once a newer release supersedes it.
  String? get skippedUpdateVersion => _prefs.getString(_skippedUpdateKey);

  /// Per-fingerprint user-assigned nicknames. The keys are device
  /// fingerprints (stable across sessions); the values are whatever the
  /// user typed (e.g. "My Laptop", "Tapiwa's phone").
  Map<String, String> get peerNicknames {
    final raw = _prefs.getString(_peerNicknamesKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return const {};
    }
  }

  /// Returns the user-assigned nickname for [fingerprint], or `null`.
  String? nicknameFor(String fingerprint) {
    if (fingerprint.isEmpty) return null;
    final value = peerNicknames[fingerprint];
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

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

  Future<void> setSkippedUpdateVersion(String? value) async {
    if (value == null) {
      await _prefs.remove(_skippedUpdateKey);
    } else {
      await _prefs.setString(_skippedUpdateKey, value);
    }
    notifyListeners();
  }

  Future<void> setNickname(String fingerprint, String? nickname) async {
    if (fingerprint.isEmpty) return;
    final current = Map<String, String>.from(peerNicknames);
    final trimmed = nickname?.trim() ?? '';
    if (trimmed.isEmpty) {
      current.remove(fingerprint);
    } else {
      current[fingerprint] = trimmed;
    }
    if (current.isEmpty) {
      await _prefs.remove(_peerNicknamesKey);
    } else {
      await _prefs.setString(_peerNicknamesKey, json.encode(current));
    }
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
