import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lanlink/core/history/transfer_history_store.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  Device buildPeer({String fingerprint = 'abc'}) {
    return Device(
      alias: 'Pixel 7',
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'Pixel 7',
      deviceType: LanLinkProtocol.deviceTypeMobile,
      fingerprint: fingerprint,
      port: LanLinkProtocol.defaultPort,
      protocol: 'https',
      ip: '192.168.1.10',
    );
  }

  TransferSession buildSession({
    required TransferStatus status,
    String sessionId = 'sess-1',
    String fingerprint = 'abc',
  }) {
    return TransferSession(
      sessionId: sessionId,
      direction: TransferDirection.send,
      peer: buildPeer(fingerprint: fingerprint),
      files: {
        'f-1': FileProgress(
          file: FileInfo(
            id: 'f-1',
            fileName: 'hello.txt',
            size: 1024,
            fileType: 'doc',
          ),
          bytes: 1024,
          status: status,
        ),
      },
      status: status,
    );
  }

  test('round-trips terminal sessions through SharedPreferences', () async {
    final store = await TransferHistoryStore.getInstance();
    final completed = buildSession(status: TransferStatus.completed);
    completed.finishedAt = DateTime.utc(2026, 1, 1, 12);
    store.scheduleSave([completed]);
    await store.flush();

    final loaded = store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.sessionId, completed.sessionId);
    expect(loaded.first.status, TransferStatus.completed);
    expect(loaded.first.peer.fingerprint, 'abc');
    expect(loaded.first.files.values.first.file.fileName, 'hello.txt');
    expect(loaded.first.finishedAt, completed.finishedAt);
  });

  test('does not persist in-flight sessions', () async {
    final store = await TransferHistoryStore.getInstance();
    store.scheduleSave([buildSession(status: TransferStatus.transferring)]);
    await store.flush();
    expect(store.load(), isEmpty);
  });

  test('clear removes the persisted entry', () async {
    final store = await TransferHistoryStore.getInstance();
    store.scheduleSave([buildSession(status: TransferStatus.completed)]);
    await store.flush();
    expect(store.load(), hasLength(1));

    await store.clear();
    expect(store.load(), isEmpty);
  });
}
