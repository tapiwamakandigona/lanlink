// E2E scenario 5 — concurrency between real peer instances:
//   * two sequential transfers from the same sender to the same receiver
//     (the API mints one TransferSession per transfer; the peer relationship
//     is what persists, so "same session" here means same live peer pair);
//   * a second sender connecting and completing a transfer while the first
//     sender's transfer is still actively in flight.

import '../tls_test_helpers.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:path/path.dart' as p;

import 'e2e_helpers.dart';

void main() {
  test('two sequential transfers over the same peer pair both succeed',
      () async {
    final tmpRoot = await Directory.systemTemp.createTemp('lanlink_e2e_seq_');
    final saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    final receiveSessions = <TransferSession>[];

    final receiver = Receiver(
      certificateProvider: testCertificateProvider,
      localDeviceProvider: () => device('peer-a-receiver', receiverFp, 0),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: receiveSessions.add,
    );
    await receiver.start();
    final port = receiver.port!;
    final sender =
        Sender(localDeviceProvider: () => device('peer-b-sender', 'fp-b', 1));
    final peer = device('peer-a-receiver', receiverFp, port);

    try {
      final srcA = await writeDeterministicFile(
          p.join(tmpRoot.path, 'first.bin'), 1024 * 1024,
          seed: 11);
      final srcB = await writeDeterministicFile(
          p.join(tmpRoot.path, 'second.bin'), 2 * 1024 * 1024,
          seed: 12);

      final infoA = fileInfoFor(srcA, fileName: 'first.bin', size: 1024 * 1024);
      final sessA = sendSessionFor(peer, [infoA]);
      await sender.send(session: sessA, peer: peer, files: [infoA]);
      expect(sessA.status, TransferStatus.completed);

      final infoB =
          fileInfoFor(srcB, fileName: 'second.bin', size: 2 * 1024 * 1024);
      final sessB = sendSessionFor(peer, [infoB]);
      await sender.send(session: sessB, peer: peer, files: [infoB]);
      expect(sessB.status, TransferStatus.completed);

      expect(receiveSessions.length, 2);
      expect(receiveSessions[0].status, TransferStatus.completed);
      expect(receiveSessions[1].status, TransferStatus.completed);
      expect(receiveSessions[0].sessionId, isNot(receiveSessions[1].sessionId),
          reason: 'each transfer gets a fresh receiver session id');

      final savedA = receiveSessions[0].files.values.single.savedPath!;
      final savedB = receiveSessions[1].files.values.single.savedPath!;
      expect(await sha256OfFile(savedA), await sha256OfFile(srcA.path));
      expect(await sha256OfFile(savedB), await sha256OfFile(srcB.path));
    } finally {
      await receiver.stop();
      try {
        await tmpRoot.delete(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('second sender completes a transfer while the first is mid-flight',
      () async {
    final tmpRoot = await Directory.systemTemp.createTemp('lanlink_e2e_conc_');
    final saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    final receiveSessions = <TransferSession>[];

    // Gate transfer A's upload (the receiver's 2nd saveDirProvider call)
    // so it is deterministically mid-flight while transfer B runs.
    final gateReached = Completer<void>();
    final gateRelease = Completer<void>();
    var saveDirCalls = 0;

    final receiver = Receiver(
      certificateProvider: testCertificateProvider,
      localDeviceProvider: () => device('peer-a-receiver', receiverFp, 0),
      saveDirProvider: () async {
        saveDirCalls++;
        if (saveDirCalls == 2) {
          gateReached.complete();
          await gateRelease.future;
        }
        return saveDir;
      },
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: receiveSessions.add,
    );
    await receiver.start();
    final port = receiver.port!;
    final peer = device('peer-a-receiver', receiverFp, port);

    try {
      final srcA = await writeDeterministicFile(
          p.join(tmpRoot.path, 'slow.bin'), 3 * 1024 * 1024,
          seed: 21);
      final srcB = await writeDeterministicFile(
          p.join(tmpRoot.path, 'quick.bin'), 512 * 1024,
          seed: 22);

      final senderA =
          Sender(localDeviceProvider: () => device('peer-b-sender', 'fp-b', 1));
      final senderB =
          Sender(localDeviceProvider: () => device('peer-c-sender', 'fp-c', 2));

      final infoA =
          fileInfoFor(srcA, fileName: 'slow.bin', size: 3 * 1024 * 1024);
      final sessA = sendSessionFor(peer, [infoA]);
      final futureA = senderA.send(session: sessA, peer: peer, files: [infoA]);

      // Wait until A's upload is genuinely in flight on the receiver…
      await gateReached.future.timeout(const Duration(seconds: 10));
      expect(receiveSessions.length, 1);

      // …then run a full second transfer from a DIFFERENT sender instance.
      final infoB = fileInfoFor(srcB, fileName: 'quick.bin', size: 512 * 1024);
      final sessB = sendSessionFor(peer, [infoB]);
      await senderB.send(
          session: sessB,
          peer: peer,
          files: [infoB]).timeout(const Duration(seconds: 30));
      expect(sessB.status, TransferStatus.completed,
          reason: 'a second sender must be able to transfer while another '
              'transfer is active');

      // Release A and let it finish.
      gateRelease.complete();
      await futureA.timeout(const Duration(seconds: 30));
      expect(sessA.status, TransferStatus.completed);

      expect(receiveSessions.length, 2);
      for (final s in receiveSessions) {
        expect(s.status, TransferStatus.completed);
      }
      final byName = {
        for (final s in receiveSessions)
          s.files.values.single.file.fileName: s.files.values.single.savedPath!,
      };
      expect(await sha256OfFile(byName['slow.bin']!),
          await sha256OfFile(srcA.path));
      expect(await sha256OfFile(byName['quick.bin']!),
          await sha256OfFile(srcB.path));
    } finally {
      if (!gateRelease.isCompleted) gateRelease.complete();
      await receiver.stop();
      try {
        await tmpRoot.delete(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
