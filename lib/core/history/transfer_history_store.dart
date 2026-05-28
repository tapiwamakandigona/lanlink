import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

/// Persists terminal-state [TransferSession] snapshots to
/// `SharedPreferences` so transfer history survives an app restart.
///
/// Only finished sessions (`completed`, `failed`, `cancelled`) are saved.
/// In-flight sessions never hit disk because we can't resume them yet.
class TransferHistoryStore {
  TransferHistoryStore._(this._prefs);

  static const _key = 'lanlink_transfer_history_v1';
  static const _maxEntries = 200;

  static TransferHistoryStore? _instance;

  /// Saves are coalesced through a microtask to avoid hammering the store
  /// when many sessions finish in quick succession.
  Timer? _flushTimer;
  List<TransferSession>? _pending;

  final SharedPreferences _prefs;

  static Future<TransferHistoryStore> getInstance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final prefs = await SharedPreferences.getInstance();
    final store = TransferHistoryStore._(prefs);
    _instance = store;
    return store;
  }

  /// Load previously persisted sessions, newest first. Malformed entries are
  /// silently dropped.
  List<TransferSession> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      final out = <TransferSession>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          out.add(TransferSession.fromJsonSnapshot(
              Map<String, dynamic>.from(entry)));
        } catch (_) {
          // skip malformed entry
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Queue a save of [sessions]. Multiple calls within ~250 ms collapse into
  /// a single write so progress updates that finish in bursts don't thrash
  /// `SharedPreferences`. Only terminal sessions are persisted.
  void scheduleSave(List<TransferSession> sessions) {
    _pending = sessions;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 250), _flush);
  }

  /// Force an immediate save. Useful in tests.
  Future<void> flush() async {
    _flushTimer?.cancel();
    await _flush();
  }

  Future<void> _flush() async {
    final pending = _pending;
    _pending = null;
    if (pending == null) return;
    final terminal = pending.where((s) {
      switch (s.status) {
        case TransferStatus.completed:
        case TransferStatus.failed:
        case TransferStatus.cancelled:
          return true;
        case TransferStatus.awaitingAccept:
        case TransferStatus.transferring:
          return false;
      }
    }).toList();
    if (terminal.isEmpty) {
      await _prefs.remove(_key);
      return;
    }
    final capped = terminal.take(_maxEntries).toList();
    final payload = json.encode(capped.map((s) => s.toJsonSnapshot()).toList());
    await _prefs.setString(_key, payload);
  }

  /// Wipe all persisted history. Used by the "Clear history" button.
  Future<void> clear() async {
    _flushTimer?.cancel();
    _pending = null;
    await _prefs.remove(_key);
  }
}
