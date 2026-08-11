// Regression tests for C2: a hostile or malformed prepare-upload response
// must fail the session cleanly (user-visible error) instead of throwing out
// of the send future and wedging the session at "transferring" forever.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:path/path.dart' as p;
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
  late File sourceFile;
  late HttpServer hostileServer;
  late int port;

  /// What the fake (hostile) receiver answers to prepare-upload.
  late Map<String, dynamic> Function(Map<String, dynamic> request)
      prepareResponse;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_c2_test_');
    sourceFile = File(p.join(tmpRoot.path, 'src.bin'));
    await sourceFile.writeAsBytes(List<int>.filled(1024, 7));

    hostileServer = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4, 0, testCertificate().securityContext());
    port = hostileServer.port;
    hostileServer.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final decoded = body.isEmpty
          ? <String, dynamic>{}
          : json.decode(body) as Map<String, dynamic>;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write(json.encode(prepareResponse(decoded)));
      await req.response.close();
    });
  });

  tearDown(() async {
    await hostileServer.close(force: true);
    try {
      await tmpRoot.delete(recursive: true);
    } catch (_) {}
  });

  Future<TransferSession> drive() async {
    final sender = Sender(localDeviceProvider: () => _device('me', 'me-fp', 1));
    final peer = _device('hostile', testCertificate().fingerprint, port);
    final info = FileInfo(
      id: const Uuid().v4(),
      fileName: 'src.bin',
      size: 1024,
      fileType: 'other',
      localPath: sourceFile.path,
    );
    final session = TransferSession(
      sessionId: 'sending-test',
      direction: TransferDirection.send,
      peer: peer,
      files: {info.id: FileProgress(file: info)},
    );
    // Must complete without throwing — errors belong in the session state.
    await sender.send(
        session: session,
        peer: peer,
        files: [info]).timeout(const Duration(seconds: 10));
    return session;
  }

  test('unknown fileId in the prepare-upload response fails the session',
      () async {
    prepareResponse = (req) => {
          'sessionId': 'evil-session',
          // A fileId the sender never offered.
          'files': {'made-up-file-id': 'some-token'},
        };
    final session = await drive();
    expect(session.status, TransferStatus.failed,
        reason: 'session must not stay stuck at transferring');
    expect(
      session.files.values.map((f) => f.error).whereType<String>(),
      isNotEmpty,
      reason: 'the failure must carry a user-visible error',
    );
  });

  test('non-string token values fail the session cleanly', () async {
    prepareResponse = (req) {
      final files = (req['files'] as Map<String, dynamic>).keys;
      return {
        'sessionId': 'evil-session',
        'files': {for (final id in files) id: 12345},
      };
    };
    final session = await drive();
    expect(session.status, TransferStatus.failed);
  });

  test('missing sessionId fails the session cleanly', () async {
    prepareResponse = (req) => {
          'files': const <String, String>{},
        };
    final session = await drive();
    expect(session.status, TransferStatus.failed);
  });

  test('non-map body fails the session cleanly', () async {
    prepareResponse = (req) => {'sessionId': null, 'files': null};
    final session = await drive();
    expect(session.status, TransferStatus.failed);
  });
}
