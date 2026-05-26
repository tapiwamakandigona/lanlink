import 'package:flutter/foundation.dart';

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

  final String sessionId;
  final TransferDirection direction;
  final Device peer;

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
  void updateBytes(String fileId, int newBytes) {
    final p = _files[fileId];
    if (p == null) return;
    p.bytes = newBytes;
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

  void markStatus(TransferStatus s) {
    status = s;
    if (s == TransferStatus.completed ||
        s == TransferStatus.cancelled ||
        s == TransferStatus.failed) {
      finishedAt = DateTime.now();
    }
    notifyListeners();
  }

  void _recomputeSpeed() {
    final elapsed =
        DateTime.now().difference(startedAt).inMilliseconds / 1000.0;
    if (elapsed <= 0) return;
    speedBytesPerSec = transferredBytes / elapsed;
  }
}
