// Regression tests for the receiver hardening fixes:
//  * B2: an upload streaming more bytes than the consented size is aborted
//    (file failed, part file dropped) instead of writing unbounded data;
//  * S3: part files are keyed per peer, so two peers sending an identically
//    named file never share (or corrupt) each other's resume state, and a
//    second concurrent writer targeting the same part file is answered 409;
//  * S6: sessions whose sender goes silent are failed by the idle reaper
//    and their upload tokens die with them.

import 'tls_test_helpers.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:path/path.dart' as p;

Device _device(String alias, String fp) => Device(
      alias: alias,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: fp,
      port: 1,
      protocol: 'https',
      ip: '127.0.0.1',
    );

void main() {
  late Directory tmpRoot;
  late Directory saveDir;
  late Receiver receiver;
  late HttpClient client;
  late int port;
  TransferSession? lastSession;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_hardening_');
    saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    lastSession = null;
    receiver = Receiver(
      certificateProvider: testCertificateProvider,
      localDeviceProvider: () => _device('receiver', 'receiver-fp'),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: (s) => lastSession = s,
      idleTimeout: const Duration(minutes: 5),
    );
    await receiver.start();
    port = receiver.port!;
    client = trustAllHttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await receiver.stop();
    try {
      await tmpRoot.delete(recursive: true);
    } catch (_) {}
  });

  Future<Map<String, dynamic>> prepare(FileInfo file,
      {String senderFp = 'sender-fp'}) async {
    final req = await client.postUrl(Uri.parse(
        'https://127.0.0.1:$port${LanLinkProtocol.routePrepareUpload}'));
    req.headers.contentType = ContentType.json;
    req.write(json.encode({
      'info': _device('sender', senderFp).toJson(),
      'files': {file.id: file.toJson()},
    }));
    final resp = await req.close();
    expect(resp.statusCode, 200);
    return json.decode(await utf8.decodeStream(resp)) as Map<String, dynamic>;
  }

  Future<HttpClientResponse> upload({
    required String sessionId,
    required String fileId,
    required String token,
    required List<int> bytes,
  }) async {
    final req = await client.postUrl(Uri.parse(
      'https://127.0.0.1:$port${LanLinkProtocol.routeUpload}'
      '?sessionId=$sessionId&fileId=$fileId&token=$token',
    ));
    req.headers.contentType = ContentType.binary;
    req.contentLength = bytes.length;
    req.add(bytes);
    return req.close();
  }

  Directory partsDir() => Directory(p.join(saveDir.path, '.lanlink_parts'));

  List<File> partFiles() => partsDir().existsSync()
      ? partsDir()
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.part'))
          .toList()
      : const <File>[];

  group('B2 consented-size enforcement', () {
    test('an upload streaming past the declared size fails the file', () async {
      const declared = 16 * 1024;
      final file = FileInfo(
        id: 'f1',
        fileName: 'evil.bin',
        size: declared,
        fileType: 'other',
      );
      final prep = await prepare(file);
      final token = (prep['files'] as Map)[file.id] as String;

      // Stream twice the consented bytes.
      final resp = await upload(
        sessionId: prep['sessionId'] as String,
        fileId: file.id,
        token: token,
        bytes: List<int>.filled(declared * 2, 0xAB),
      );
      await resp.drain<void>();
      expect(resp.statusCode, 400);

      expect(lastSession, isNotNull);
      expect(lastSession!.status, TransferStatus.failed);
      expect(lastSession!.files[file.id]!.status, TransferStatus.failed);
      expect(lastSession!.files[file.id]!.error, contains('consented size'));

      // No finished file, and the untrustworthy part file is gone too.
      expect(
        saveDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('evil.bin')),
        isEmpty,
      );
      expect(partFiles(), isEmpty);
    });

    test('an exact-size upload still completes', () async {
      final payload = List<int>.generate(8 * 1024, (i) => i & 0xff);
      final file = FileInfo(
        id: 'f2',
        fileName: 'good.bin',
        size: payload.length,
        fileType: 'other',
      );
      final prep = await prepare(file);
      final token = (prep['files'] as Map)[file.id] as String;
      final resp = await upload(
        sessionId: prep['sessionId'] as String,
        fileId: file.id,
        token: token,
        bytes: payload,
      );
      await resp.drain<void>();
      expect(resp.statusCode, 200);
      expect(lastSession!.status, TransferStatus.completed);
      final saved = saveDir
          .listSync()
          .whereType<File>()
          .singleWhere((f) => f.path.endsWith('good.bin'));
      expect(saved.readAsBytesSync(), payload);
    });
  });

  group('S3 per-peer part files', () {
    test('resume state from one peer is invisible to another peer', () async {
      final payload = List<int>.generate(32 * 1024, (i) => (i * 7) & 0xff);
      final file = FileInfo(
        id: 'f3',
        fileName: 'shared-name.bin',
        size: payload.length,
        fileType: 'other',
      );

      // Peer A: interrupted upload leaves a part file behind.
      final prepA = await prepare(file, senderFp: 'peer-a');
      final tokenA = (prepA['files'] as Map)[file.id] as String;
      // Big enough to overflow the client's output buffer so bytes are
      // actually on the wire before the abort (mirrors the resume test).
      const cut = 24 * 1024;
      final req = await client.postUrl(Uri.parse(
        'https://127.0.0.1:$port${LanLinkProtocol.routeUpload}'
        '?sessionId=${prepA['sessionId']}&fileId=${file.id}&token=$tokenA',
      ));
      req.headers.contentType = ContentType.binary;
      req.contentLength = payload.length;
      req.add(payload.sublist(0, cut));
      await req.flush();
      // Let the server consume the flushed bytes before dropping the line.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      req.abort();

      // Wait for the partial bytes to settle on disk. The abort races the
      // server's stream consumption, so accept whatever non-empty prefix
      // made it and assert the resume offset matches it exactly.
      File? part;
      var settled = 0;
      for (var i = 0; i < 100; i++) {
        final candidates = partFiles();
        if (candidates.length == 1) {
          final len = candidates.single.lengthSync();
          if (len > 0 && len == settled) {
            part = candidates.single;
            break;
          }
          settled = len;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(part, isNotNull, reason: 'expected a surviving part file');
      expect(settled, greaterThan(0));
      expect(settled, lessThan(payload.length));

      // Peer B offering the same name+size must NOT be offered a resume
      // into peer A's bytes.
      final prepB = await prepare(file, senderFp: 'peer-b');
      expect(prepB.containsKey('resume'), isFalse,
          reason: "peer B must not resume into peer A's part file");

      // Peer A itself still gets its resume offset back.
      final prepA2 = await prepare(file, senderFp: 'peer-a');
      final resume = prepA2['resume'] as Map<String, dynamic>;
      expect(resume[file.id], settled);
    });

    test('a second concurrent writer to the same part file is answered 409',
        () async {
      final payload = List<int>.generate(64 * 1024, (i) => i & 0xff);
      final file = FileInfo(
        id: 'f4',
        fileName: 'contended.bin',
        size: payload.length,
        fileType: 'other',
      );

      // Session 1 starts uploading and stalls mid-body (socket held open).
      final prep1 = await prepare(file);
      final token1 = (prep1['files'] as Map)[file.id] as String;
      final req1 = await client.postUrl(Uri.parse(
        'https://127.0.0.1:$port${LanLinkProtocol.routeUpload}'
        '?sessionId=${prep1['sessionId']}&fileId=${file.id}&token=$token1',
      ));
      req1.headers.contentType = ContentType.binary;
      req1.contentLength = payload.length;
      req1.add(payload.sublist(0, 16 * 1024));
      await req1.flush();

      // Give the server a moment to open the part file.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Session 2 (same peer, same file) tries to write the same part file.
      final prep2 = await prepare(file);
      final token2 = (prep2['files'] as Map)[file.id] as String;
      final resp2 = await upload(
        sessionId: prep2['sessionId'] as String,
        fileId: file.id,
        token: token2,
        bytes: payload,
      );
      await resp2.drain<void>();
      expect(resp2.statusCode, 409,
          reason: 'concurrent writers must never interleave one part file');

      req1.abort();
    });
  });

  group('S6 idle reaper', () {
    test('a session with no sender activity past idleTimeout is failed',
        () async {
      final file = FileInfo(
        id: 'f5',
        fileName: 'ghost.bin',
        size: 1024,
        fileType: 'other',
      );
      final prep = await prepare(file);
      final token = (prep['files'] as Map)[file.id] as String;
      final session = lastSession!;
      expect(session.status, TransferStatus.transferring);

      // A reap "now" is harmless: activity is fresh.
      receiver.reapIdleSessions();
      expect(session.status, TransferStatus.transferring);

      // Six minutes of silence: the reaper fails the session.
      receiver.reapIdleSessions(
          now: DateTime.now().add(const Duration(minutes: 6)));
      expect(session.status, TransferStatus.failed);
      expect(session.files[file.id]!.status, TransferStatus.failed);
      expect(session.files[file.id]!.error, contains('No activity'));

      // The session is gone from the pending map: its token is dead.
      final resp = await upload(
        sessionId: prep['sessionId'] as String,
        fileId: file.id,
        token: token,
        bytes: List<int>.filled(1024, 1),
      );
      await resp.drain<void>();
      expect(resp.statusCode, 404);
    });
  });
}
