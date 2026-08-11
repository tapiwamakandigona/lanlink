// E2E scenario — sending from an Android SAF `content://` source instead of
// a filesystem path: the sender must stream the bytes through its injected
// content opener (no local copy) and the receiver must land a hash-identical
// file. Guards the zero-copy pick flow (FileInfo.contentUri).

import '../tls_test_helpers.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:path/path.dart' as p;

import 'e2e_helpers.dart';

void main() {
  late Directory tmpRoot;
  late Directory saveDir;
  late Receiver receiver;
  late int port;
  TransferSession? receiveSession;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_e2e_content_');
    saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    receiveSession = null;

    receiver = Receiver(
      certificateProvider: testCertificateProvider,
      localDeviceProvider: () => device('peer-a-receiver', receiverFp, 0),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: (s) => receiveSession = s,
    );
    await receiver.start();
    port = receiver.port!;
  });

  tearDown(() async {
    await receiver.stop();
    try {
      await tmpRoot.delete(recursive: true);
    } catch (_) {}
  });

  test('content:// source streams through the opener and arrives intact',
      () async {
    // The "document": a ~3MB binary blob backed by a temp file — the opener
    // below plays the role of the SAF platform channel.
    final src = File(p.join(tmpRoot.path, 'blob.bin'));
    final bytes = List<int>.generate(3 * 1024 * 1024 + 137, (i) => i % 251);
    await src.writeAsBytes(bytes, flush: true);

    final openedOffsets = <int>[];
    final sender = Sender(
      localDeviceProvider: () => device('peer-b-sender', 'fp-b', 1),
      contentOpener: (uri, startAt) {
        expect(uri, 'content://lanlink.test/blob');
        openedOffsets.add(startAt);
        return src.openRead(startAt);
      },
    );

    final info = FileInfo(
      id: 'content-file-1',
      fileName: 'blob.bin',
      size: bytes.length,
      fileType: 'other',
      contentUri: 'content://lanlink.test/blob',
      // Deliberately no localPath: the sender must not touch the filesystem
      // for this file except through the opener.
    );
    final peer = device('peer-a-receiver', receiverFp, port);
    final session = sendSessionFor(peer, [info]);

    await sender.send(session: session, peer: peer, files: [info]);

    expect(session.status, TransferStatus.completed,
        reason: 'send from a content URI must complete');
    expect(openedOffsets, [0],
        reason: 'fresh transfer must open the stream at byte 0');
    expect(receiveSession, isNotNull);
    expect(receiveSession!.status, TransferStatus.completed);

    final received = File(p.join(saveDir.path, 'blob.bin'));
    expect(await received.exists(), isTrue);
    expect(
      sha256.convert(await received.readAsBytes()),
      sha256.convert(bytes),
      reason: 'received bytes must be identical to the source',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('vanished content source fails the file, not the process', () async {
    final sender = Sender(
      localDeviceProvider: () => device('peer-b-sender', 'fp-b', 1),
      contentOpener: (uri, startAt) =>
          Stream.error(const FileSystemException('document gone')),
    );
    final info = FileInfo(
      id: 'content-file-2',
      fileName: 'gone.bin',
      size: 1024,
      fileType: 'other',
      contentUri: 'content://lanlink.test/gone',
    );
    final peer = device('peer-a-receiver', receiverFp, port);
    final session = sendSessionFor(peer, [info]);

    await sender.send(session: session, peer: peer, files: [info]);

    expect(session.status, TransferStatus.failed,
        reason: 'a dead content stream must fail the session cleanly');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
