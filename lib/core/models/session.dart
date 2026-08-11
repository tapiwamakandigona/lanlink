import 'package:flutter/foundation.dart';

import '../protocol/constants.dart';
import 'device.dart';
import 'file_info.dart';

/// Direction of a [TransferSession].
enum TransferDirection { send, receive }

/// Lifecycle status for a [TransferSession].
enum TransferStatus {
  /// Receiver is waiting for the local user to accept or decline.
  awaitingAccept,

  /// Sender or receiver is actively transferring bytes.
  transferring,

  /// Transfer succeeded (all files finished).
  completed,

  /// Transfer was cancelled by either side.
  cancelled,

  /// Transfer failed mid-stream.
  failed,
}

/// A single per-file progress record.
class FileProgress {
  FileProgress({
    required this.file,
    this.bytes = 0,
    this.status = TransferStatus.transferring,
    this.error,
    this.savedPath,
  });

  final FileInfo file;
  int bytes;
  TransferStatus status;
  String? error;
  String? savedPath;

  double get fraction => file.size == 0 ? 1.0 : bytes / file.size;
}

/// Tracks a single send or receive session across one or more files.
///
/// Sessions are observable [ChangeNotifier]s so the UI can subscribe to
/// progress without polling.
class TransferSession extends ChangeNotifier {
  TransferSession({
    required this.sessionId,
    required this.direction,
    required this.peer,
    required Map<String, FileProgress> files,
    this.status = TransferStatus.transferring,
  }) : _files = files;

  /// Local identifier for this session. For send sessions this is initially
  /// a "pending-…" placeholder; once `prepare-upload` returns it is updated
  /// to the receiver-assigned sessionId so cancel requests can be addressed
  /// to the right session on the receiver.
  String sessionId;
  final TransferDirection direction;
  final Device peer;

  /// Optional group identifier. Sessions that belong to one logical
  /// "conversation" with a peer (e.g. the user tapped "+ Add files" while a
  /// transfer card was still visible) share a groupId so the UI can render
  /// them as a single grouped card. Assigned by AppState; null for
  /// standalone sessions.
  String? groupId;

  final Map<String, FileProgress> _files;
  Map<String, FileProgress> get files => Map.unmodifiable(_files);

  TransferStatus status;
  DateTime startedAt = DateTime.now();
  DateTime? finishedAt;

  /// Per-session bytes/sec rolling estimate.
  double speedBytesPerSec = 0;

  int get totalBytes => _files.values.fold<int>(0, (a, b) => a + b.file.size);

  int get transferredBytes => _files.values.fold<int>(0, (a, b) => a + b.bytes);

  double get fraction => totalBytes == 0 ? 1.0 : transferredBytes / totalBytes;

  /// Update a file's byte counter and recompute speed; notifies listeners.
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  void updateBytes(String fileId, int newBytes) {
    final p = _files[fileId];
    if (p == null) return;
    final done = newBytes >= p.file.size;
    final firstBytes = p.bytes == 0 && newBytes > 0;
    p.bytes = newBytes;
    // Streaming transfers call this for every network chunk (tens of
    // thousands of times for a large file). Recomputing speed and rebuilding
    // the UI per chunk burns CPU that should go to disk/network I/O, so
    // throttle the observable side to ~10 updates per second. The first
    // chunk and the final byte count always notify so the UI reacts
    // immediately to a transfer starting or finishing.
    final now = DateTime.now();
    if (!done &&
        !firstBytes &&
        now.difference(_lastProgressNotify) <
            const Duration(milliseconds: 100)) {
      return;
    }
    _lastProgressNotify = now;
    _recomputeSpeed();
    notifyListeners();
  }

  void markFile(String fileId, TransferStatus s,
      {String? error, String? savedPath}) {
    final p = _files[fileId];
    if (p == null) return;
    p.status = s;
    p.error = error;
    p.savedPath = savedPath;
    notifyListeners();
  }

  /// True once the session has reached a terminal state.
  bool get isTerminal =>
      status == TransferStatus.completed ||
      status == TransferStatus.cancelled ||
      status == TransferStatus.failed;

  void markStatus(TransferStatus s) {
    // Terminal states are sticky: once a session is cancelled/failed/
    // completed nothing may flip it to another status. This closes the
    // cancel/upload race where a still-running upload marked a cancelled
    // session back to completed.
    if (isTerminal && s != status) return;
    status = s;
    if (s == TransferStatus.completed ||
        s == TransferStatus.cancelled ||
        s == TransferStatus.failed) {
      finishedAt = DateTime.now();
    }
    notifyListeners();
  }

  /// (timestamp, transferredBytes) samples inside the trailing window.
  final List<(DateTime, int)> _speedSamples = [];

  /// Trailing window for the live speed estimate. A lifetime average lies
  /// after any speed change (a mid-transfer Wi-Fi dip kept the display —
  /// and the ETA computed from it — wrong for minutes); a short window
  /// tracks what the link does *now* while still smoothing chunk jitter.
  static const speedWindow = Duration(seconds: 5);

  void _recomputeSpeed({DateTime? now}) {
    final at = now ?? DateTime.now();
    final total = transferredBytes;
    _speedSamples.add((at, total));
    final cutoff = at.subtract(speedWindow);
    while (
        _speedSamples.length > 1 && _speedSamples.first.$1.isBefore(cutoff)) {
      _speedSamples.removeAt(0);
    }
    final (firstAt, firstBytes) = _speedSamples.first;
    final dt = at.difference(firstAt).inMilliseconds / 1000.0;
    if (dt < 0.2) {
      // Not enough window yet (transfer just started): lifetime average is
      // the best available estimate and avoids a wild first reading.
      final elapsed = at.difference(startedAt).inMilliseconds / 1000.0;
      if (elapsed > 0) speedBytesPerSec = total / elapsed;
      return;
    }
    speedBytesPerSec = (total - firstBytes) / dt;
  }

  /// Test hook: recompute the speed as if called at [now].
  @visibleForTesting
  void recomputeSpeedAt(DateTime now) => _recomputeSpeed(now: now);

  /// Snapshot the terminal state of this session as a JSON-serializable map
  /// suitable for persisting to history. Only finished sessions
  /// (`completed`, `failed`, `cancelled`) should be persisted — restoring an
  /// in-flight session across restarts is not currently supported.
  Map<String, dynamic> toJsonSnapshot() => {
        'sessionId': sessionId,
        'direction': direction.name,
        'status': status.name,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        'peer': {
          'alias': peer.alias,
          'fingerprint': peer.fingerprint,
          'deviceModel': peer.deviceModel,
          'deviceType': peer.deviceType,
          'ip': peer.ip,
          'port': peer.port,
          'protocol': peer.protocol,
        },
        'files': _files.values
            .map((p) => {
                  'id': p.file.id,
                  'fileName': p.file.fileName,
                  'size': p.file.size,
                  'fileType': p.file.fileType,
                  'bytes': p.bytes,
                  'status': p.status.name,
                  if (p.error != null) 'error': p.error,
                  if (p.savedPath != null) 'savedPath': p.savedPath,
                  // Persisted so a restored send session can be retried.
                  if (p.file.localPath != null) 'localPath': p.file.localPath,
                })
            .toList(),
      };

  /// Reconstruct a session from a snapshot produced by [toJsonSnapshot]. The
  /// returned session is "frozen" — listeners are not wired and progress
  /// will not advance. Intended for display in history.
  static TransferSession fromJsonSnapshot(Map<String, dynamic> json) {
    final peerJson =
        Map<String, dynamic>.from(json['peer'] as Map? ?? const {});
    final peer = Device(
      alias: (peerJson['alias'] as String?) ?? 'Unknown device',
      version: LanLinkProtocol.protocolVersion,
      deviceModel: (peerJson['deviceModel'] as String?) ?? '',
      deviceType: (peerJson['deviceType'] as String?) ??
          LanLinkProtocol.deviceTypeHeadless,
      fingerprint: (peerJson['fingerprint'] as String?) ?? '',
      port: (peerJson['port'] as num?)?.toInt() ?? LanLinkProtocol.defaultPort,
      protocol: (peerJson['protocol'] as String?) ?? 'http',
      ip: (peerJson['ip'] as String?) ?? '0.0.0.0',
    );
    final filesJson = (json['files'] as List?) ?? const [];
    final files = <String, FileProgress>{};
    for (final raw in filesJson) {
      final map = Map<String, dynamic>.from(raw as Map);
      final id = (map['id'] as String?) ?? '';
      if (id.isEmpty) continue;
      final fileInfo = FileInfo(
        id: id,
        fileName: (map['fileName'] as String?) ?? 'unknown',
        size: (map['size'] as num?)?.toInt() ?? 0,
        fileType: (map['fileType'] as String?) ?? 'other',
        localPath: map['localPath'] as String?,
      );
      files[id] = FileProgress(
        file: fileInfo,
        bytes: (map['bytes'] as num?)?.toInt() ?? 0,
        status: _statusFromName(map['status'] as String?),
        error: map['error'] as String?,
        savedPath: map['savedPath'] as String?,
      );
    }
    final session = TransferSession(
      sessionId: (json['sessionId'] as String?) ?? '',
      direction: _directionFromName(json['direction'] as String?),
      peer: peer,
      files: files,
      status: _statusFromName(json['status'] as String?),
    );
    final startedRaw = json['startedAt'] as String?;
    if (startedRaw != null) {
      session.startedAt = DateTime.tryParse(startedRaw) ?? DateTime.now();
    }
    final finishedRaw = json['finishedAt'] as String?;
    if (finishedRaw != null) {
      session.finishedAt = DateTime.tryParse(finishedRaw);
    }
    return session;
  }

  static TransferStatus _statusFromName(String? name) {
    return TransferStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => TransferStatus.completed,
    );
  }

  static TransferDirection _directionFromName(String? name) {
    return TransferDirection.values.firstWhere(
      (d) => d.name == name,
      orElse: () => TransferDirection.send,
    );
  }
}
