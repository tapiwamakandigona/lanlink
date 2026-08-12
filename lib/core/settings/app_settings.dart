import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../connectivity/connectivity_mode.dart';
import '../onboarding/pairing_choice.dart';
import '../protocol/constants.dart';

/// Persistent user-facing settings.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static const _aliasKey = 'lanlink_alias';
  static const _portKey = 'lanlink_port';
  static const _saveDirKey = 'lanlink_save_dir';
  static const _quickSaveKey = 'lanlink_quick_save';
  static const _trustedKey = 'lanlink_trusted_fingerprints';
  static const _trustedAliasKey = 'lanlink_trusted_aliases';
  static const _connectivityModeKey = 'lanlink_connectivity_mode';
  static const _hotspotRoleKey = 'lanlink_hotspot_role';
  static const _autoUpdateKey = 'lanlink_auto_update_check';
  static const _themeModeKey = 'lanlink_theme_mode';
  static const _skippedUpdateKey = 'lanlink_skipped_update_version';
  static const _peerNicknamesKey = 'lanlink_peer_nicknames';
  static const _lastOnboardedVersionKey = 'lanlink_last_onboarded_version';
  static const _lastPairingKey = 'lanlink_last_pairing_v1';
  static const _connectivityDefaultAppliedKey =
      'lanlink_connectivity_default_applied_v1';

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
    if (name != null && name.isNotEmpty) {
      final mode = ConnectivityMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => _platformDefaultConnectivity(),
      );
      return mode.isAvailable ? mode : _platformDefaultConnectivity();
    }
    return _platformDefaultConnectivity();
  }

  /// Platform-aware default: phones with their own hotspot (Android) get
  /// the Hotspot mode out of the box because that's the headline real-world
  /// use case; everything else (desktop, iOS) defaults to LAN auto-discovery.
  static ConnectivityMode _platformDefaultConnectivity() {
    if (Platform.isAndroid) return ConnectivityMode.hotspot;
    return ConnectivityMode.lan;
  }

  /// Ensures the platform-aware connectivity default is materialised once
  /// per install. Called at startup so the chip on the home screen reflects
  /// the real default we now ship with, instead of the old LAN-everywhere
  /// behaviour that pre-3.2.0 builds wrote into shared_preferences.
  Future<void> ensureConnectivityDefault() async {
    if (_prefs.getBool(_connectivityDefaultAppliedKey) == true) return;
    final existing = _prefs.getString(_connectivityModeKey);
    if (existing == null || existing.isEmpty) {
      await _prefs.setString(
        _connectivityModeKey,
        _platformDefaultConnectivity().name,
      );
    }
    await _prefs.setBool(_connectivityDefaultAppliedKey, true);
    notifyListeners();
  }

  HotspotRole get hotspotRole {
    final name = _prefs.getString(_hotspotRoleKey);
    return HotspotRole.values.firstWhere(
      (role) => role.name == name,
      orElse: () => HotspotRole.auto,
    );
  }

  bool get autoUpdateCheck => _prefs.getBool(_autoUpdateKey) ?? true;

  /// User-chosen theme mode (system | light | dark). Defaults to system.
  String get themeModeRaw => _prefs.getString(_themeModeKey) ?? 'system';

  Future<void> setThemeMode(String value) async {
    await _prefs.setString(_themeModeKey, value);
    notifyListeners();
  }

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

  /// The app version whose onboarding the user has already seen. Empty/absent
  /// means they have never completed onboarding. Used by [SplashGate] to
  /// decide whether to show the welcome carousel on launch (first run) and
  /// again after an update bumps the version.
  String get lastOnboardedVersion =>
      _prefs.getString(_lastOnboardedVersionKey) ?? '';

  Future<void> setLastOnboardedVersion(String value) async {
    await _prefs.setString(_lastOnboardedVersionKey, value);
    notifyListeners();
  }

  /// Clears the onboarded marker so the carousel replays on next launch.
  /// Wired to the "Replay tutorial" button in Settings.
  Future<void> resetOnboarding() async {
    await _prefs.remove(_lastOnboardedVersionKey);
    notifyListeners();
  }

  /// User-recorded last pairing pick from the wizard. Used to offer a
  /// "Same as last time" shortcut on the next launch so returning users
  /// don't have to re-answer the same two questions.
  PairingChoice? get lastPairing =>
      PairingChoice.decode(_prefs.getString(_lastPairingKey));

  Future<void> setLastPairing(PairingChoice? value) async {
    if (value == null) {
      await _prefs.remove(_lastPairingKey);
    } else {
      await _prefs.setString(_lastPairingKey, value.encode());
    }
    notifyListeners();
  }

  static const _pinnedKey = 'lanlink_pinned_fingerprints_v1';

  /// Fingerprints pinned after a successful connect. A device presenting a
  /// pinned fingerprint is shown as verified; a device presenting a familiar
  /// alias with an unpinned fingerprint is NOT.
  Set<String> get pinnedFingerprints {
    final raw = _prefs.getString(_pinnedKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (json.decode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  bool isPinned(String fingerprint) =>
      fingerprint.isNotEmpty && pinnedFingerprints.contains(fingerprint);

  /// Pins [fingerprint] so the peer shows as verified from now on.
  Future<void> pinFingerprint(String fingerprint) async {
    if (fingerprint.isEmpty) return;
    final set = pinnedFingerprints..add(fingerprint);
    await _prefs.setString(_pinnedKey, json.encode(set.toList()));
    notifyListeners();
  }

  Future<void> unpinFingerprint(String fingerprint) async {
    final set = pinnedFingerprints..remove(fingerprint);
    if (set.isEmpty) {
      await _prefs.remove(_pinnedKey);
    } else {
      await _prefs.setString(_pinnedKey, json.encode(set.toList()));
    }
    notifyListeners();
  }

  /// Marks [fingerprint] as trusted for Quick Save auto-accept. The
  /// optional [alias] is only a display label for the Settings list; trust
  /// itself is keyed on the fingerprint alone.
  Future<void> trust(String fingerprint, {String? alias}) async {
    final set = trustedFingerprints..add(fingerprint);
    await _prefs.setString(_trustedKey, json.encode(set.toList()));
    if (alias != null && alias.trim().isNotEmpty) {
      final aliases = _trustedAliases..[fingerprint] = alias.trim();
      await _prefs.setString(_trustedAliasKey, json.encode(aliases));
    }
    notifyListeners();
  }

  Future<void> untrust(String fingerprint) async {
    final set = trustedFingerprints..remove(fingerprint);
    await _prefs.setString(_trustedKey, json.encode(set.toList()));
    final aliases = _trustedAliases;
    if (aliases.remove(fingerprint) != null) {
      await _prefs.setString(_trustedAliasKey, json.encode(aliases));
    }
    notifyListeners();
  }

  /// The display label recorded when [fingerprint] was trusted, if any.
  String? trustedAliasFor(String fingerprint) => _trustedAliases[fingerprint];

  Map<String, String> get _trustedAliases {
    final raw = _prefs.getString(_trustedAliasKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      return (json.decode(raw) as Map).cast<String, String>();
    } catch (_) {
      return <String, String>{};
    }
  }
}
