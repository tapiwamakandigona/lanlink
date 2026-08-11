// Regression tests for the C1 cancel/upload race in the receiver:
//  * upload tokens are single-use (replay => 401, no part-file corruption);
//  * a cancelled session stays cancelled — an in-flight upload must stop
//    writing and must not flip the session back to completed;
//  * failed sessions are dropped from the pending map so their tokens die.

import 'tls_test_helpers.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

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
  TransferSession? lastReceiveSession;
  late Dio dio;

  // Hooks tests can override per-case.
  Future<Directory> Function()? saveDirOverride;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('lanlink_c1_test_');
    saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    saveDirOverride = null;
    lastReceiveSession = null;

    receiver = Receiver(
      certificateProvider: testCertificateProvider,
      localDeviceProvider: () => _device('receiver', 'receiver-fp', 0),
      saveDirProvider: () =>
          saveDirOverride != null ? saveDirOverride!() : Future.value(saveDir),
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: (s) => lastReceiveSession = s,
    );
    await receiver.start();
    port = receiver.port!;
    dio = trustAllDio(BaseOptions(
      baseUrl: 'https://127.0.0.1:$port',
      responseType: ResponseType.plain,
      validateStatus: (s) => s != null,
    ));
  });

  tearDown(() async {
    await receiver.stop();
    try {
      await tmpRoot.delete(recursive: true);
    } catch (_) {}
  });

  Future<({String sessionId, Map<String, String> tokens})> prepare(
      List<FileInfo> files) async {
    final resp = await dio.post<String>(
      LanLinkProtocol.routePrepareUpload,
      data: {
        'info': _device('sender', 'sender-fp', 1).toJson(),
        'files': {for (final f in files) f.id: f.toJson()},
      },
    );
    expect(resp.statusCode, 200);
    final data = json.decode(resp.data!) as Map<String, dynamic>;
    return (
      sessionId: data['sessionId'] as String,
      tokens: Map<String, String>.from(data['files'] as Map),
    );
  }

  Future<Response<String>> upload({
    required String sessionId,
    required String fileId,
    required String token,
    required Object body,
    int? contentLength,
  }) {
    return dio.post<String>(
      LanLinkProtocol.routeUpload,
      queryParameters: {
        'sessionId': sessionId,
        'fileId': fileId,
        'token': token,
      },
      data: body,
      options: Options(
        contentType: 'application/octet-stream',
        headers: contentLength != null
            ? {HttpHeaders.contentLengthHeader: '$contentLength'}
            : null,
      ),
    );
  }

  test('upload token is single-use: replay is rejected with 401', () async {
    final content = List<int>.generate(1024, (i) => i % 251);
    final f = FileInfo(
      id: const Uuid().v4(),
      fileName: 'once.bin',
      size: content.length,
      fileType: 'other',
    );
    // A second file keeps the session active after the first completes, so
    // the replay hits a live session (the interesting case).
    final other = FileInfo(
      id: const Uuid().v4(),
      fileName: 'other.bin',
      size: 8,
      fileType: 'other',
    );
    final prep = await prepare([f, other]);
    final token = prep.tokens[f.id]!;

    final first = await upload(
      sessionId: prep.sessionId,
      fileId: f.id,
      token: token,
      body: Stream.fromIterable([content]),
      contentLength: content.length,
    );
    expect(first.statusCode, 200);

    // Replay the same token with different bytes: must be rejected and must
    // not touch what was saved.
    final replay = await upload(
      sessionId: prep.sessionId,
      fileId: f.id,
      token: token,
      body: Stream.fromIterable([List<int>.filled(content.length, 0)]),
      contentLength: content.length,
    );
    expect(replay.statusCode, 401,
        reason: 'a consumed upload token must be rejected with 401');

    final saved = File(p.join(saveDir.path, 'once.bin'));
    expect(await saved.exists(), isTrue);
    expect(await saved.readAsBytes(), content,
        reason: 'the replay must not corrupt the saved file');
  });

  test(
      'cancel mid-upload: writing stops, the session stays cancelled and is '
      'never flipped back to completed', () async {
    const chunkSize = 64 * 1024;
    final chunk1 = List<int>.filled(chunkSize, 1);
    final chunk2 = List<int>.filled(chunkSize, 2);
    final f = FileInfo(
      id: const Uuid().v4(),
      fileName: 'race.bin',
      size: chunkSize * 2,
      fileType: 'other',
    );
    final prep = await prepare([f]);
    final session = lastReceiveSession!;

    final cancelled = Completer<void>();
    Stream<List<int>> body() async* {
      yield chunk1;
      // Cancel the session while this upload is still streaming.
      final resp = await dio.post<String>(
        LanLinkProtocol.routeCancel,
        queryParameters: {'sessionId': prep.sessionId},
      );
      expect(resp.statusCode, 200);
      cancelled.complete();
      yield chunk2;
    }

    // The receiver may either answer 403 or drop the connection mid-body —
    // both are correct "not acknowledged" outcomes; a 200 is the bug.
    int? statusCode;
    try {
      final uploadResp = await upload(
        sessionId: prep.sessionId,
        fileId: f.id,
        token: prep.tokens[f.id]!,
        body: body(),
        contentLength: chunkSize * 2,
      );
      statusCode = uploadResp.statusCode;
    } on DioException catch (_) {
      statusCode = null; // connection aborted: fine
    }
    await cancelled.future;

    expect(statusCode, isNot(200),
        reason: 'an upload racing a cancel must not be acknowledged');
    expect(session.status, TransferStatus.cancelled,
        reason: 'the in-flight upload must not flip a cancelled session');
    expect(session.files[f.id]!.status, isNot(TransferStatus.completed));
    final finalFile = File(p.join(saveDir.path, 'race.bin'));
    expect(await finalFile.exists(), isFalse,
        reason: 'a cancelled upload must not be finalized to the save dir');
  });

  test(
      'cancel mid-upload: the post-abort drain is bounded — a peer that '
      'keeps streaming past 32MB gets the connection terminated', () async {
    const chunkSize = 1024 * 1024;
    final chunk = List<int>.filled(chunkSize, 7);
    const totalSize = 512 * 1024 * 1024; // far past the drain bound
    final f = FileInfo(
      id: const Uuid().v4(),
      fileName: 'flood.bin',
      size: totalSize,
      fileType: 'other',
    );
    final prep = await prepare([f]);
    final session = lastReceiveSession!;

    var sentBytes = 0;
    var cancelSent = false;
    Stream<List<int>> body() async* {
      yield chunk;
      sentBytes += chunkSize;
      // Cancel the session while this upload is still streaming…
      final resp = await dio.post<String>(
        LanLinkProtocol.routeCancel,
        queryParameters: {'sessionId': prep.sessionId},
      );
      expect(resp.statusCode, 200);
      cancelSent = true;
      // …then keep flooding. The receiver must stop reading once its
      // bounded drain is exhausted, which kills this stream.
      while (sentBytes < totalSize) {
        yield chunk;
        sentBytes += chunkSize;
      }
    }

    int? statusCode;
    try {
      final uploadResp = await upload(
        sessionId: prep.sessionId,
        fileId: f.id,
        token: prep.tokens[f.id]!,
        body: body(),
        contentLength: totalSize,
      );
      statusCode = uploadResp.statusCode;
    } on DioException catch (_) {
      statusCode = null; // connection aborted mid-body: the desired outcome
    }

    expect(cancelSent, isTrue);
    expect(statusCode, isNot(200),
        reason: 'a flooded post-cancel upload must never be acknowledged');
    // 32MB drain bound + generous slack for socket/dio buffering. Without
    // the bound the receiver would drink all 512MB.
    expect(sentBytes, lessThan(64 * 1024 * 1024),
        reason: 'the mid-stream abort drain must stop past the 32MB bound');
    expect(session.status, TransferStatus.cancelled);
  });

  test('uploads to a cancelled session are rejected outright', () async {
    final f = FileInfo(
      id: const Uuid().v4(),
      fileName: 'late.bin',
      size: 4,
      fileType: 'other',
    );
    final prep = await prepare([f]);
    receiver.cancelSession(prep.sessionId);
    expect(lastReceiveSession!.status, TransferStatus.cancelled);

    final resp = await upload(
      sessionId: prep.sessionId,
      fileId: f.id,
      token: prep.tokens[f.id]!,
      body: Stream.fromIterable([
        [1, 2, 3, 4]
      ]),
      contentLength: 4,
    );
    expect(resp.statusCode, anyOf(403, 404),
        reason: 'stale tokens for a cancelled session must stay dead');
    expect(lastReceiveSession!.status, TransferStatus.cancelled);
  });

  test('a failed session is dropped from pending: its tokens go stale',
      () async {
    final a = FileInfo(
        id: const Uuid().v4(), fileName: 'a.bin', size: 2, fileType: 'other');
    final b = FileInfo(
        id: const Uuid().v4(), fileName: 'b.bin', size: 2, fileType: 'other');
    final prep = await prepare([a, b]);

    // Make the first upload fail hard (save dir unavailable).
    saveDirOverride = () async => throw const FileSystemException('boom');
    final failed = await upload(
      sessionId: prep.sessionId,
      fileId: a.id,
      token: prep.tokens[a.id]!,
      body: Stream.fromIterable([
        [1, 2]
      ]),
      contentLength: 2,
    );
    expect(failed.statusCode, 500);
    expect(lastReceiveSession!.status, TransferStatus.failed);

    // The session is now terminal: the other (unused, otherwise valid)
    // token must be dead because the session left the pending map.
    saveDirOverride = null;
    final stale = await upload(
      sessionId: prep.sessionId,
      fileId: b.id,
      token: prep.tokens[b.id]!,
      body: Stream.fromIterable([
        [3, 4]
      ]),
      contentLength: 2,
    );
    expect(stale.statusCode, 404,
        reason: 'failed sessions must be removed from the pending map');
    expect(lastReceiveSession!.status, TransferStatus.failed,
        reason: 'the failed session must stay failed');
  });

  test('terminal session statuses are sticky on the model', () {
    final f = FileInfo(id: 'x', fileName: 'x.bin', size: 1, fileType: 'other');
    final s = TransferSession(
      sessionId: 's',
      direction: TransferDirection.receive,
      peer: _device('peer', 'fp', 1),
      files: {'x': FileProgress(file: f)},
    );
    s.markStatus(TransferStatus.cancelled);
    s.markStatus(TransferStatus.completed);
    expect(s.status, TransferStatus.cancelled);
    s.markStatus(TransferStatus.failed);
    expect(s.status, TransferStatus.cancelled);
  });
}
