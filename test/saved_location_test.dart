import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/ui/shell/saved_location.dart';

FileInfo _file(String name, {int size = 10}) =>
    FileInfo(id: name, fileName: name, size: size, fileType: 'other');

TransferSession _session(Map<String, String?> filesToSavedPaths) {
  return TransferSession(
    sessionId: 's1',
    direction: TransferDirection.receive,
    peer: Device(
      alias: 'Peer',
      version: '2.0',
      deviceModel: 'test',
      deviceType: 'desktop',
      fingerprint: 'fp',
      port: 53317,
      protocol: 'http',
      ip: '127.0.0.1',
    ),
    files: {
      for (final e in filesToSavedPaths.entries)
        e.key: FileProgress(
          file: _file(e.key),
          status: TransferStatus.completed,
          savedPath: e.value,
        )
    },
    status: TransferStatus.completed,
  );
}

void main() {
  group('singleSavedFileFor', () {
    test('one saved file -> its path', () {
      final s = _session({'a.jpg': '/dl/a.jpg'});
      expect(singleSavedFileFor(s), '/dl/a.jpg');
    });

    test('multiple saved files -> null (ambiguous)', () {
      final s = _session({'a.jpg': '/dl/a.jpg', 'b.jpg': '/dl/b.jpg'});
      expect(singleSavedFileFor(s), isNull);
    });

    test('no recorded paths -> null', () {
      final s = _session({'a.jpg': null, 'b.jpg': ''});
      expect(singleSavedFileFor(s), isNull);
    });

    test('one saved among unrecorded -> the saved one', () {
      final s = _session({'a.jpg': null, 'b.jpg': '/dl/b.jpg'});
      expect(singleSavedFileFor(s), '/dl/b.jpg');
    });
  });

  group('savedFolderFor', () {
    test('derives folder from first saved path', () {
      final s = _session({'a.jpg': '/dl/sub/a.jpg'});
      expect(savedFolderFor(s), '/dl/sub');
    });

    test('null when nothing recorded', () {
      final s = _session({'a.jpg': null});
      expect(savedFolderFor(s), isNull);
    });
  });
}
