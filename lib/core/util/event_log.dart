import 'package:flutter/foundation.dart';

/// A tiny in-memory ring buffer of recent app events, used to power the
/// "Copy diagnostics" button in Settings. Nothing here is persisted or sent
/// anywhere — it only exists so a user reporting a problem can paste a short
/// log into a message instead of describing it from memory.
class EventLog {
  EventLog._();

  static final EventLog instance = EventLog._();

  static const int maxEntries = 200;

  final List<EventLogEntry> _entries = <EventLogEntry>[];

  List<EventLogEntry> get entries => List.unmodifiable(_entries);

  /// Append a line. Oldest entries roll off once [maxEntries] is reached.
  void add(String message, {EventLevel level = EventLevel.info}) {
    final entry = EventLogEntry(
      time: DateTime.now(),
      level: level,
      message: message,
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    if (kDebugMode) {
      debugPrint('[event:${level.name}] $message');
    }
  }

  void clear() => _entries.clear();

  /// Render the buffer as a single clipboard-friendly string, oldest first.
  String export({String? header}) {
    final buffer = StringBuffer();
    if (header != null && header.isNotEmpty) {
      buffer.writeln(header);
      buffer.writeln('-' * 32);
    }
    for (final e in _entries) {
      buffer.writeln(e.format());
    }
    return buffer.toString().trimRight();
  }
}

enum EventLevel { info, warn, error }

class EventLogEntry {
  EventLogEntry({
    required this.time,
    required this.level,
    required this.message,
  });

  final DateTime time;
  final EventLevel level;
  final String message;

  String format() {
    final t = time.toIso8601String();
    return '$t  ${level.name.toUpperCase().padRight(5)}  $message';
  }
}
