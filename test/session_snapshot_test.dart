import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';

void main() {
  test('send snapshot preserves localPath so a restored session can retry', () {
    final peer = Device(
      alias: 'Laptop',
      version: '2.0',
      deviceModel: 'x',
      deviceType: 'desktop',
      fingerprint: 'fp-1',
      port: 53317,
      protocol: 'https',
      ip: '192.168.1.5',
    );
    final session = TransferSession(
      sessionId: 's1',
      direction: TransferDirection.send,
      peer: peer,
      files: {
        'f1': FileProgress(
          file: FileInfo(
            id: 'f1',
            fileName: 'photo.jpg',
            size: 1234,
            fileType: 'image',
            localPath: '/tmp/photo.jpg',
          ),
          status: TransferStatus.failed,
        ),
      },
      status: TransferStatus.failed,
    );

    final restored = TransferSession.fromJsonSnapshot(session.toJsonSnapshot());

    expect(restored.direction, TransferDirection.send);
    expect(restored.status, TransferStatus.failed);
    expect(restored.files['f1']!.file.localPath, '/tmp/photo.jpg');
  });

  test('restored snapshots never retain active transfer states', () {
    for (final status in ['awaitingAccept', 'transferring']) {
      final restored = TransferSession.fromJsonSnapshot({
        'sessionId': 'stale-$status',
        'direction': 'receive',
        'status': status,
        'peer': {
          'alias': 'Old peer',
          'ip': '192.168.1.7',
          'port': 53317,
          'protocol': 'https',
        },
        'files': [
          {
            'id': 'f1',
            'fileName': 'unfinished.bin',
            'size': 100,
            'bytes': 40,
            'status': status,
          },
        ],
      });

      expect(restored.status, TransferStatus.failed, reason: status);
      expect(restored.isTerminal, isTrue, reason: status);
      expect(restored.files['f1']!.status, TransferStatus.failed);
      expect(restored.files['f1']!.error, contains('interrupted'));
    }
  });
}
