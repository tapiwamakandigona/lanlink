// E2E scenario 3 — bidirectional cancel between two real peer instances:
//   * sender-initiated cancel mid-transfer,
//   * receiver-initiated cancel mid-transfer,
// asserting both sides end in a clean cancelled (never failed/completed)
// state, no finalized file appears in the save dir, and any partial data is
// confined to the clearly-marked `.lanlink_parts` staging area.

import '../tls_test_helpers.dart';
import 'dart:async';
import 'dart:io';

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
  late File sourceFile;
  late Receiver receiver;
  late int port;
  TransferSession? receiveSession;

  // Gate: block the receiver's second saveDirProvider call (the upload
  // handler) until released, so we can cancel deterministically while the
  // upload is genuinely in flight (same technique as transfer_cancel_test).
  late Completer<void> uploadGateReached;
  late Completer<void> uploadGateRelease;
  int saveDirCalls = 0;

  const srcSize = 4 * 1024 * 1024;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_e2e_cancel_');
    saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    sourceFile = await writeDeterministicFile(
        p.join(tmpRoot.path, 'big.bin'), srcSize,
        seed: 7);

    receiveSession = null;
    saveDirCalls = 0;
    uploadGateReached = Completer<void>();
    uploadGateRelease = Completer<void>();

    receiver = Receiver(
      certificateProvider: testCertificateProvider,
      localDeviceProvider: () => device('peer-a-receiver', receiverFp, 0),
      saveDirProvider: () async {
        saveDirCalls++;
        if (saveDirCalls == 2) {
          uploadGateReached.complete();
          await uploadGateRelease.future;
        }
        return saveDir;
      },
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: (s) => receiveSession = s,
    );
    await receiver.start();
    port = receiver.port!;
  });

  tearDown(() async {
    if (!uploadGateRelease.isCompleted) uploadGateRelease.complete();
    await receiver.stop();
    try {
      await tmpRoot.delete(recursive: true);
    } catch (_) {}
  });

  (Sender, TransferSession, FileInfo) buildSend() {
    final sender =
        Sender(localDeviceProvider: () => device('peer-b-sender', 'fp-b', 1));
    final peer = device('peer-a-receiver', receiverFp, port);
    final info = fileInfoFor(sourceFile, fileName: 'big.bin', size: srcSize);
    final session = sendSessionFor(peer, [info]);
    return (sender, session, info);
  }

  Future<void> assertNoFinalizedOutput() async {
    // No finalized file may exist in the save dir; partial bytes are only
    // allowed inside the clearly-marked `.lanlink_parts` staging folder
    // (kept deliberately as a resume head start).
    final entries = await saveDir.list(recursive: false).toList();
    final visible = entries
        .map((e) => p.basename(e.path))
        .where((n) => n != '.lanlink_parts')
        .toList();
    expect(visible, isEmpty,
        reason: 'a cancelled transfer must not leave finalized files in the '
            'save dir (found: $visible)');
    final partsDir = Directory(p.join(saveDir.path, '.lanlink_parts'));
    if (await partsDir.exists()) {
      await for (final e in partsDir.list()) {
        expect(p.basename(e.path), endsWith('.part'),
            reason: 'staged partials must be clearly marked as .part files');
      }
    }
  }

  test('sender-initiated cancel mid-transfer: both sides end cancelled',
      () async {
    final (sender, session, info) = buildSend();
    final peer = device('peer-a-receiver', receiverFp, port);
    final sendFuture = sender.send(session: session, peer: peer, files: [info]);

    await uploadGateReached.future.timeout(const Duration(seconds: 10));
    expect(receiveSession, isNotNull);

    // Sender-side user hits Cancel while the upload is in flight.
    await sender.cancelSend(session: session, peer: peer);
    uploadGateRelease.complete();
    await sendFuture.timeout(const Duration(seconds: 15));

    expect(session.status, TransferStatus.cancelled,
        reason: 'sender session must end cancelled, not failed');
    expect(session.files[info.id]!.status, TransferStatus.cancelled);

    // The /cancel dial reaches the real receiver instance.
    await waitFor(() => receiveSession!.status == TransferStatus.cancelled);
    expect(
        receiveSession!.files.values
            .any((f) => f.status == TransferStatus.completed),
        isFalse);
    await assertNoFinalizedOutput();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('receiver-initiated cancel mid-transfer: both sides end cancelled',
      () async {
    final (sender, session, info) = buildSend();
    final peer = device('peer-a-receiver', receiverFp, port);
    final sendFuture = sender.send(session: session, peer: peer, files: [info]);

    await uploadGateReached.future.timeout(const Duration(seconds: 10));
    expect(receiveSession, isNotNull);

    // Receiver-side user hits Stop while the upload is in flight.
    receiver.cancelSession(receiveSession!.sessionId);
    expect(receiveSession!.status, TransferStatus.cancelled);
    uploadGateRelease.complete();

    await sendFuture.timeout(const Duration(seconds: 15));
    expect(session.status, TransferStatus.cancelled,
        reason: 'the sender must surface the receiver stop as cancelled, '
            'not as a generic failure');
    expect(session.files[info.id]!.status, TransferStatus.cancelled);
    await assertNoFinalizedOutput();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
