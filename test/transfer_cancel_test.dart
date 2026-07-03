// Behavioral tests for real bidirectional cancellation (finding 4):
//  * the sender can stop an in-flight send: HTTP work aborts promptly, the
//    peer's /cancel route is dialed, and both sides end up cancelled;
//  * the receiver stopping its session mid-upload also surfaces as a
//    cancelled (not failed) session on the sending side.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

Device _device(String alias, String fp, int port) => Device(
      alias: alias,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: fp,
      port: port,
      protocol: 'http',
      ip: '127.0.0.1',
    );

Future<void> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not reached within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory tmpRoot;
  late Directory saveDir;
  late File sourceFile;
  late Receiver receiver;
  late int port;
  TransferSession? receiveSession;

  // Gate: the receiver's save-dir provider blocks its second call (the
  // upload) until released, so the test can deterministically act while the
  // upload is in flight.
  late Completer<void> uploadGateReached;
  late Completer<void> uploadGateRelease;
  int saveDirCalls = 0;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_cancel_test_');
    saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    sourceFile = File(p.join(tmpRoot.path, 'big.bin'));
    await sourceFile.writeAsBytes(List<int>.filled(2 * 1024 * 1024, 42));

    receiveSession = null;
    saveDirCalls = 0;
    uploadGateReached = Completer<void>();
    uploadGateRelease = Completer<void>();

    receiver = Receiver(
      localDeviceProvider: () => _device('receiver', 'receiver-fp', 0),
      saveDirProvider: () async {
        saveDirCalls++;
        if (saveDirCalls == 2) {
          // The upload handler is now running.
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

  (Sender, Device, FileInfo, TransferSession) buildSend() {
    final sender = Sender(
      localDeviceProvider: () => _device('sender', 'sender-fp', 1),
    );
    final peer = _device('receiver', 'receiver-fp', port);
    final info = FileInfo(
      id: const Uuid().v4(),
      fileName: 'big.bin',
      size: 2 * 1024 * 1024,
      fileType: 'other',
      localPath: sourceFile.path,
    );
    final session = TransferSession(
      sessionId: 'sending-test',
      direction: TransferDirection.send,
      peer: peer,
      files: {info.id: FileProgress(file: info)},
    );
    return (sender, peer, info, session);
  }

  test('sender cancel aborts the in-flight send and notifies the receiver',
      () async {
    final (sender, peer, info, session) = buildSend();
    final sendFuture = sender.send(session: session, peer: peer, files: [info]);

    // Wait until the upload is genuinely in flight on the receiver.
    await uploadGateReached.future.timeout(const Duration(seconds: 10));
    expect(receiveSession, isNotNull);

    await sender.cancelSend(session: session, peer: peer);
    uploadGateRelease.complete();
    await sendFuture.timeout(const Duration(seconds: 10));

    expect(session.status, TransferStatus.cancelled,
        reason: 'the outgoing session must end cancelled, not failed');
    expect(session.files[info.id]!.status, TransferStatus.cancelled);

    // The peer was dialed on /cancel, so the receiver session ends too.
    await _waitFor(() => receiveSession!.status == TransferStatus.cancelled);
    final finalFile = File(p.join(saveDir.path, 'big.bin'));
    expect(await finalFile.exists(), isFalse);
  });

  test('receiver-side stop surfaces as cancelled on the sending side',
      () async {
    final (sender, peer, info, session) = buildSend();
    final sendFuture = sender.send(session: session, peer: peer, files: [info]);

    await uploadGateReached.future.timeout(const Duration(seconds: 10));
    expect(receiveSession, isNotNull);

    // Local user hits Stop on the receiving device.
    receiver.cancelSession(receiveSession!.sessionId);
    expect(receiveSession!.status, TransferStatus.cancelled);
    uploadGateRelease.complete();

    await sendFuture.timeout(const Duration(seconds: 10));
    expect(session.status, TransferStatus.cancelled,
        reason: "the sender must learn about the receiver's cancellation "
            'and not report a generic failure');
  });
}
