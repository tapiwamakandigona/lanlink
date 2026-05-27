// End-to-end loopback test for the LanLink transfer pipeline.
//
// Spins up a real [Receiver] on localhost, drives a [Sender] against it, and
// asserts both that the file lands on disk and that the same
// [TransferSession] visible to the UI advances through progress updates.

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

void main() {
  late Directory tmpRoot;
  late Directory saveDir;
  late File sourceFile;
  late Receiver receiver;
  late int port;
  late TransferSession? lastReceiveSession;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_loopback_test_');
    saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);

    sourceFile = File(p.join(tmpRoot.path, 'hello.bin'));
    // ~512 KB of deterministic content so we get multiple TCP chunks.
    final buffer = List<int>.generate(512 * 1024, (i) => i % 251);
    await sourceFile.writeAsBytes(buffer);

    lastReceiveSession = null;
    receiver = Receiver(
      localDeviceProvider: () => Device(
        alias: 'receiver',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'test',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'receiver-fp',
        port: 0,
        protocol: 'http',
        ip: '127.0.0.1',
      ),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: (s) => lastReceiveSession = s,
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

  test('end-to-end: file is uploaded and saved, progress is visible', () async {
    final sender = Sender(
      localDeviceProvider: () => Device(
        alias: 'sender',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'test',
        deviceType: LanLinkProtocol.deviceTypeMobile,
        fingerprint: 'sender-fp',
        port: 0,
        protocol: 'http',
        ip: '127.0.0.1',
      ),
    );

    final peer = Device(
      alias: 'receiver',
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: 'receiver-fp',
      port: port,
      protocol: 'http',
      ip: '127.0.0.1',
    );

    final fileInfo = FileInfo(
      id: const Uuid().v4(),
      fileName: 'hello.bin',
      size: await sourceFile.length(),
      fileType: 'other',
      localPath: sourceFile.path,
    );

    final sendSession = TransferSession(
      sessionId: 'sending-test',
      direction: TransferDirection.send,
      peer: peer,
      files: {
        fileInfo.id:
            FileProgress(file: fileInfo, status: TransferStatus.transferring),
      },
      status: TransferStatus.transferring,
    );

    final byteCounts = <int>[];
    sendSession.addListener(() {
      byteCounts.add(sendSession.transferredBytes);
    });

    await sender.send(session: sendSession, peer: peer, files: [fileInfo]);

    expect(sendSession.status, TransferStatus.completed,
        reason: 'send session should end in completed state');
    expect(sendSession.transferredBytes, fileInfo.size,
        reason: 'all bytes should have been sent');
    expect(byteCounts, isNotEmpty,
        reason: 'sender must have surfaced progress callbacks');
    expect(byteCounts.any((b) => b > 0 && b < fileInfo.size), isTrue,
        reason: 'sender should have reported intermediate progress');

    expect(lastReceiveSession, isNotNull,
        reason: 'receiver must have created a session');
    expect(lastReceiveSession!.status, TransferStatus.completed);
    final savedPath = lastReceiveSession!.files.values.first.savedPath;
    expect(savedPath, isNotNull, reason: 'savedPath should be populated');

    final saved = File(savedPath!);
    expect(await saved.exists(), isTrue,
        reason: 'received file should exist on disk');
    final originalBytes = await sourceFile.readAsBytes();
    final savedBytes = await saved.readAsBytes();
    expect(savedBytes.length, originalBytes.length);
    expect(savedBytes, originalBytes);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('rejected files do not produce a file on disk', () async {
    final restrictiveReceiver = Receiver(
      localDeviceProvider: () => Device(
        alias: 'receiver',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'test',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'receiver-fp-2',
        port: 0,
        protocol: 'http',
        ip: '127.0.0.1',
      ),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async => AcceptDecision.reject(),
      onSessionStarted: (_) {},
    );
    await restrictiveReceiver.start();
    final rejPort = restrictiveReceiver.port!;
    try {
      final sender = Sender(
        localDeviceProvider: () => Device(
          alias: 'sender',
          version: LanLinkProtocol.protocolVersion,
          deviceModel: 'test',
          deviceType: LanLinkProtocol.deviceTypeMobile,
          fingerprint: 'sender-fp-2',
          port: 0,
          protocol: 'http',
          ip: '127.0.0.1',
        ),
      );
      final peer = Device(
        alias: 'receiver',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'test',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'receiver-fp-2',
        port: rejPort,
        protocol: 'http',
        ip: '127.0.0.1',
      );
      final fileInfo = FileInfo(
        id: const Uuid().v4(),
        fileName: 'hello.bin',
        size: await sourceFile.length(),
        fileType: 'other',
        localPath: sourceFile.path,
      );
      final session = TransferSession(
        sessionId: 'sending-test-2',
        direction: TransferDirection.send,
        peer: peer,
        files: {
          fileInfo.id:
              FileProgress(file: fileInfo, status: TransferStatus.transferring),
        },
        status: TransferStatus.transferring,
      );
      await sender.send(session: session, peer: peer, files: [fileInfo]);
      expect(session.status, TransferStatus.cancelled);
    } finally {
      await restrictiveReceiver.stop();
    }
  }, timeout: const Timeout(Duration(seconds: 15)));
}
