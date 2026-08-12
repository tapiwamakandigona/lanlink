// Regression test for BUG-10: when one parallel upload fails, the sibling
// uploads (in flight or still queued) are aborted via the shared cancel
// token, but their workers return early without marking anything. Before the
// fix, those file rows stayed at `transferring` forever inside a `failed`
// session — and were persisted that way in history.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:path/path.dart' as p;

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
  late HttpServer server;
  late int port;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_sibling_test_');
    server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4, 0, testCertificate().securityContext());
    port = server.port;
  });

  tearDown(() async {
    await server.close(force: true);
    try {
      await tmpRoot.delete(recursive: true);
    } catch (_) {}
  });

  test('one failed upload leaves no sibling file stuck at transferring',
      () async {
    // Three 256 KiB source files so the "slow" uploads genuinely stream.
    final files = <FileInfo>[];
    for (var i = 0; i < 3; i++) {
      final f = File(p.join(tmpRoot.path, 'f$i.bin'));
      await f.writeAsBytes(List<int>.filled(256 * 1024, i));
      files.add(FileInfo(
        id: 'file-$i',
        fileName: 'f$i.bin',
        size: 256 * 1024,
        fileType: 'other',
        localPath: f.path,
      ));
    }

    // Receiver stub: prepare-upload accepts all three; upload of file-0
    // fails immediately with 500, uploads of file-1/file-2 stall (drain
    // slowly) so they are mid-flight when file-0's worker fails the
    // session and fires the shared cancel token.
    server.listen((req) async {
      if (req.uri.path == LanLinkProtocol.routePrepareUpload) {
        await utf8.decoder.bind(req).join();
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(json.encode({
          'sessionId': 'sess-1',
          'files': {for (final f in files) f.id: 'tok-${f.id}'},
        }));
        await req.response.close();
        return;
      }
      if (req.uri.path == LanLinkProtocol.routeUpload) {
        final fileId = req.uri.queryParameters['fileId'];
        if (fileId == 'file-0') {
          // Fail fast without reading the body.
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }
        // Stall: read the body very slowly so the upload is still in
        // flight when file-0 fails. The client-side cancel token aborts
        // this request; any error here is expected.
        try {
          await for (final _ in req) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          req.response.statusCode = 200;
          await req.response.close();
        } catch (_) {}
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });

    final sender = Sender(
      localDeviceProvider: () => _device('me', 'me-fp', 1),
      maxParallelUploads: 3,
    );
    final peer = _device('peer', testCertificate().fingerprint, port);
    final session = TransferSession(
      sessionId: 'sending-test',
      direction: TransferDirection.send,
      peer: peer,
      files: {for (final f in files) f.id: FileProgress(file: f)},
    );

    await sender
        .send(session: session, peer: peer, files: files)
        .timeout(const Duration(seconds: 30));

    expect(session.status, TransferStatus.failed,
        reason: 'file-0 hard-failed with 500');
    expect(session.files['file-0']!.status, TransferStatus.failed);

    // The core regression: NO file may remain in a non-terminal state.
    for (final f in files) {
      final st = session.files[f.id]!.status;
      expect(
        st == TransferStatus.completed ||
            st == TransferStatus.failed ||
            st == TransferStatus.cancelled,
        isTrue,
        reason: '${f.id} left non-terminal ($st) in a failed session',
      );
    }
  });
}
