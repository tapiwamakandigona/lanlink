// B3 (security review): transport is HTTPS with certificate-hash pinning.
//
// The device fingerprint is the SHA-256 of the TLS certificate DER. The
// sender accepts a connection IFF the presented cert hash matches the pinned
// fingerprint; with no pin (first contact) it accepts and RECORDS the hash
// (trust-on-first-use). These tests drive the REAL Receiver + Sender over
// loopback TLS.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/security/device_certificate.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'tls_test_helpers.dart';

Device _device(String alias, String fp, int port) => Device(
      alias: alias,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: fp,
      port: port,
      protocol: 'https',
      ip: '127.0.0.1',
    );

void main() {
  late Directory tmpRoot;
  late Directory saveDir;
  late Receiver receiver;
  late int port;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_tls_test_');
    saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    receiver = Receiver(
      certificateProvider: testCertificateProvider,
      localDeviceProvider: () =>
          _device('receiver', testCertificate().fingerprint, 0),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: (_) {},
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

  test('sender rejects a server whose cert hash != pinned fingerprint',
      () async {
    final sender = Sender(localDeviceProvider: () => _device('me', 'me', 1));
    // Pin a DIFFERENT (but real) certificate's fingerprint: the handshake
    // must be aborted — the peer never even sees the request.
    final impostorPin = testCertificateB().fingerprint;
    expect(impostorPin, isNot(testCertificate().fingerprint));

    final probed = await sender.probe(_device('receiver', impostorPin, port));
    expect(probed, isNull,
        reason: 'a cert-hash mismatch against a pinned fingerprint '
            'must never be accepted');

    // A full send against the mismatched pin must fail, not transfer.
    final src = File(p.join(tmpRoot.path, 'secret.bin'));
    await src.writeAsBytes(List<int>.filled(2048, 42));
    final info = FileInfo(
      id: const Uuid().v4(),
      fileName: 'secret.bin',
      size: 2048,
      fileType: 'other',
      localPath: src.path,
    );
    final session = TransferSession(
      sessionId: 'sending-tls-test',
      direction: TransferDirection.send,
      peer: _device('receiver', impostorPin, port),
      files: {
        info.id: FileProgress(file: info, status: TransferStatus.transferring),
      },
      status: TransferStatus.transferring,
    );
    await sender.send(
      session: session,
      peer: _device('receiver', impostorPin, port),
      files: [info],
    );
    expect(session.status, TransferStatus.failed);
    expect(File(p.join(saveDir.path, 'secret.bin')).existsSync(), isFalse);
  });

  test('first contact (no pin) records the cert hash — trust-on-first-use',
      () async {
    final sender = Sender(localDeviceProvider: () => _device('me', 'me', 1));
    // Empty fingerprint = no pin yet (discovery/subnet probing).
    final found = await sender.probe(_device('unknown', '', port));
    expect(found, isNotNull);
    // The recorded fingerprint is the hash of the certificate actually
    // presented in the handshake — not whatever JSON the peer reported.
    expect(found!.fingerprint, testCertificate().fingerprint);
    expect(sender.pinner.observed('127.0.0.1', port),
        testCertificate().fingerprint);
  });

  test('full transfer over TLS with the correct pinned fingerprint succeeds',
      () async {
    final sender = Sender(localDeviceProvider: () => _device('me', 'me', 1));
    final peer = _device('receiver', testCertificate().fingerprint, port);

    final src = File(p.join(tmpRoot.path, 'hello.bin'));
    final payload = List<int>.generate(64 * 1024, (i) => i % 251);
    await src.writeAsBytes(payload);
    final info = FileInfo(
      id: const Uuid().v4(),
      fileName: 'hello.bin',
      size: payload.length,
      fileType: 'other',
      localPath: src.path,
    );
    final session = TransferSession(
      sessionId: 'sending-tls-ok',
      direction: TransferDirection.send,
      peer: peer,
      files: {
        info.id: FileProgress(file: info, status: TransferStatus.transferring),
      },
      status: TransferStatus.transferring,
    );
    await sender.send(session: session, peer: peer, files: [info]);
    expect(session.status, TransferStatus.completed);
    final saved = File(p.join(saveDir.path, 'hello.bin'));
    expect(saved.existsSync(), isTrue);
    expect(await saved.readAsBytes(), payload);
  });

  test('DeviceCertificate persists across loads; fingerprint is cert-derived',
      () async {
    SharedPreferences.setMockInitialValues({});
    DeviceCertificate.debugResetCache();
    final first = await DeviceCertificate.load();
    expect(first.fingerprint,
        DeviceCertificate.fingerprintOfPem(first.certificatePem));
    DeviceCertificate.debugResetCache();
    final second = await DeviceCertificate.load();
    expect(second.fingerprint, first.fingerprint,
        reason: 'the persisted certificate must be reused, not regenerated');
    expect(second.certificatePem, first.certificatePem);
    DeviceCertificate.debugResetCache();
  });
}
