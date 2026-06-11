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
  static const _connectivityModeKey = 'lanlink_connectivity_mode';
  static const _hotspotRoleKey = 'lanlink_hotspot_role';
  static const _autoUpdateKey = 'lanlink_auto_update_check';
  static const _themeModeKey = 'lanlink_theme_mode';
  static const _skippedUpdateKey = 'lanlink_skipped_update_version';
  static const _peerNicknamesKey = 'lanlink_peer_nicknames';
  static const _lastOnboardedVersionKey = 'lanlink_last_onboarded_version';
  static const _lastPairingKey = 'lanlink_last_pairing_v1';
  static const _wizardModeKey = 'lanlink_wizard_mode_v1';
  static const _connectivityDefaultAppliedKey =
      'lanlink_connectivity_default_applied_v1';
  static const _hapticsKey = 'lanlink_haptics_enabled';
  static const _simpleModeKey = 'lanlink_simple_mode_v1';
  static const _simpleModeExitButtonKey = 'lanlink_simple_exit_button_v1';

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
      return ConnectivityMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => _platformDefaultConnectivity(),
      );
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

  /// Whether the launch-time pairing wizard should be shown. Three modes:
  ///   * `auto`  — show the wizard until the user has paired once, then
  ///               offer a "Same as last time" card. (Default.)
  ///   * `always`— always show the wizard at launch.
  ///   * `never` — power-user mode; skip straight to the home screen.
  String get wizardMode => _prefs.getString(_wizardModeKey) ?? 'auto';

  Future<void> setWizardMode(String value) async {
    await _prefs.setString(_wizardModeKey, value);
    notifyListeners();
  }

  /// Whether to play a soft vibration / chime on transfer completion.
  /// Defaults to true on phones, false on desktop where it'd be weird.
  bool get hapticsEnabled =>
      _prefs.getBool(_hapticsKey) ?? (Platform.isAndroid || Platform.isIOS);

  Future<void> setHapticsEnabled(bool value) async {
    await _prefs.setBool(_hapticsKey, value);
    notifyListeners();
  }

  /// Whether the pared-down "Simple mode" UI is active. Designed for
  /// non-technical users (grandparents, kids): two giant buttons, plain
  /// language, no jargon, transport details hidden entirely.
  bool get simpleMode => _prefs.getBool(_simpleModeKey) ?? false;

  Future<void> setSimpleMode(bool value) async {
    await _prefs.setBool(_simpleModeKey, value);
    notifyListeners();
  }

  /// Whether the Simple-mode home screen shows the "Full version" exit
  /// button. A caregiver can hide it from Settings so a relative can't
  /// accidentally tap into the full UI and get lost.
  bool get simpleModeExitButton =>
      _prefs.getBool(_simpleModeExitButtonKey) ?? true;

  Future<void> setSimpleModeExitButton(bool value) async {
    await _prefs.setBool(_simpleModeExitButtonKey, value);
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
