// E2E scenario 1 — full happy path between two real peer instances over
// loopback: pair via a single-use connect token, then transfer
//   * a small text file,
//   * a ~5MB binary file,
//   * a folder with nested files,
// verifying every received file is sha256-identical to its source.

import '../tls_test_helpers.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:path/path.dart' as p;

import 'e2e_helpers.dart';

void main() {
  late Directory tmpRoot;
  late Directory saveDir;
  late Receiver receiver;
  late Sender sender;
  late int port;
  TransferSession? receiveSession;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_e2e_happy_');
    saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    receiveSession = null;

    // Peer instance A: real Receiver hosting an HTTP server on 127.0.0.1.
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

    // Peer instance B: real Sender.
    sender =
        Sender(localDeviceProvider: () => device('peer-b-sender', 'fp-b', 1));
  });

  tearDown(() async {
    await receiver.stop();
    try {
      await tmpRoot.delete(recursive: true);
    } catch (_) {}
  });

  test('pair/connect handshake succeeds before transferring', () async {
    // Pairing: receiver mints a single-use connect token (what its QR code
    // carries); the sender redeems it over a real socket and learns the
    // receiver's identity.
    final token = receiver.issueConnectToken();
    final stub = device('unknown', '', port);
    final learned = await sender.connectWithToken(stub, token);
    expect(learned, isNotNull, reason: 'connect handshake must succeed');
    expect(learned!.fingerprint, receiverFp);
    expect(learned.alias, 'peer-a-receiver');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('small text file arrives hash-identical', () async {
    final src = File(p.join(tmpRoot.path, 'note.txt'));
    await src.writeAsString('Hello from LanLink e2e.\nLine two — ünïcode ✓\n');
    final size = await src.length();
    final info = fileInfoFor(src, fileName: 'note.txt', size: size);
    final peer = device('peer-a-receiver', receiverFp, port);
    final session = sendSessionFor(peer, [info]);

    await sender.send(session: session, peer: peer, files: [info]);

    expect(session.status, TransferStatus.completed);
    expect(receiveSession, isNotNull);
    expect(receiveSession!.status, TransferStatus.completed);
    final savedPath = receiveSession!.files.values.single.savedPath;
    expect(savedPath, isNotNull);
    expect(await sha256OfFile(savedPath!), await sha256OfFile(src.path),
        reason: 'received text file must be byte-identical');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('~5MB binary file arrives hash-identical', () async {
    const size = 5 * 1024 * 1024 + 12345; // not chunk-aligned on purpose
    final src = await writeDeterministicFile(
        p.join(tmpRoot.path, 'blob.bin'), size,
        seed: 42);
    final info = fileInfoFor(src, fileName: 'blob.bin', size: size);
    final peer = device('peer-a-receiver', receiverFp, port);
    final session = sendSessionFor(peer, [info]);

    final progress = <int>[];
    session.addListener(() => progress.add(session.transferredBytes));

    await sender.send(session: session, peer: peer, files: [info]);

    expect(session.status, TransferStatus.completed);
    expect(session.transferredBytes, size);
    expect(progress.any((b) => b > 0 && b < size), isTrue,
        reason: 'transfer must stream with intermediate progress');
    expect(receiveSession!.status, TransferStatus.completed);
    final savedPath = receiveSession!.files.values.single.savedPath!;
    expect(await File(savedPath).length(), size);
    expect(await sha256OfFile(savedPath), await sha256OfFile(src.path),
        reason: 'received binary must be byte-identical');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('folder with nested files arrives structure-intact and hash-identical',
      () async {
    // Build a source folder: Trip/readme.txt, Trip/photos/p1.bin,
    // Trip/photos/raw/p2.bin — folder transfers carry the relative path in
    // FileInfo.fileName (see folder_transfer_test.dart).
    final srcDir = Directory(p.join(tmpRoot.path, 'Trip'));
    await Directory(p.join(srcDir.path, 'photos', 'raw'))
        .create(recursive: true);
    final readme = File(p.join(srcDir.path, 'readme.txt'));
    await readme.writeAsString('trip notes');
    final p1 = await writeDeterministicFile(
        p.join(srcDir.path, 'photos', 'p1.bin'), 300 * 1024,
        seed: 1);
    final p2 = await writeDeterministicFile(
        p.join(srcDir.path, 'photos', 'raw', 'p2.bin'), 700 * 1024,
        seed: 2);

    final infos = [
      fileInfoFor(readme,
          fileName: 'Trip/readme.txt', size: await readme.length()),
      fileInfoFor(p1, fileName: 'Trip/photos/p1.bin', size: 300 * 1024),
      fileInfoFor(p2, fileName: 'Trip/photos/raw/p2.bin', size: 700 * 1024),
    ];
    final peer = device('peer-a-receiver', receiverFp, port);
    final session = sendSessionFor(peer, infos);

    await sender.send(session: session, peer: peer, files: infos);

    expect(session.status, TransferStatus.completed);
    expect(receiveSession!.status, TransferStatus.completed);
    expect(receiveSession!.files.length, 3);

    // Every file re-created under saveDir with the folder structure and
    // identical bytes.
    final expected = {
      'Trip/readme.txt': readme.path,
      'Trip/photos/p1.bin': p1.path,
      'Trip/photos/raw/p2.bin': p2.path,
    };
    for (final fp in receiveSession!.files.values) {
      expect(fp.status, TransferStatus.completed);
      final savedPath = fp.savedPath!;
      final rel = p
          .relative(savedPath, from: saveDir.path)
          .replaceAll(Platform.pathSeparator, '/');
      expect(expected.containsKey(rel), isTrue,
          reason: 'unexpected relative path: $rel');
      expect(await sha256OfFile(savedPath), await sha256OfFile(expected[rel]!),
          reason: '$rel must be byte-identical');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
