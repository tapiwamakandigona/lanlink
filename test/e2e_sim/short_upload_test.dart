// A sender that declares size=N in prepare-upload but streams fewer than N
// bytes (Content-Length matching the short body) must NOT have its file
// marked completed — that would be a silently truncated file shown as done.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:dio/dio.dart';
import '../tls_test_helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('short body (received < declared size) is not marked completed',
      () async {
    final saveDir =
        await Directory.systemTemp.createTemp('ll_short_upload_test');
    TransferSession? started;
    final receiver = Receiver(
      localDeviceProvider: () => device('rx', receiverFp, 0).copyWith(),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept({for (final f in files) f.id}),
      onSessionStarted: (s) => started = s,
      certificateProvider: testCertificateProvider,
    );
    await receiver.start();
    addTearDown(() async {
      await receiver.stop();
      await saveDir.delete(recursive: true);
    });

    final port = receiver.port!;
    final dio = trustAllDio();

    // prepare-upload: declare a 1000-byte file.
    const declared = 1000;
    final fileId = uuid.v4();
    final prep = await dio.postUri<Map<String, dynamic>>(
      Uri(
          scheme: 'https',
          host: '127.0.0.1',
          port: port,
          path: LanLinkProtocol.routePrepareUpload),
      data: {
        'info': device('tx', 'txfp', 0).toJson(),
        'files': {
          fileId: FileInfo(
                  id: fileId,
                  fileName: 'short.bin',
                  size: declared,
                  fileType: 'other')
              .toJson(),
        },
      },
      options: Options(responseType: ResponseType.json),
    );
    final token = (prep.data!['files'] as Map)[fileId] as String;

    // upload: stream only 500 bytes with a matching Content-Length.
    final short = List<int>.filled(500, 7);
    int status = -1;
    try {
      final resp = await dio.postUri<dynamic>(
        Uri(
            scheme: 'https',
            host: '127.0.0.1',
            port: port,
            path: LanLinkProtocol.routeUpload,
            queryParameters: {
              'sessionId': prep.data!['sessionId'],
              'fileId': fileId,
              'token': token,
            }),
        data: Stream.fromIterable([short]),
        options: Options(
          contentType: 'application/octet-stream',
          headers: {HttpHeaders.contentLengthHeader: '500'},
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      status = resp.statusCode ?? -1;
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final fileStatus = started?.files[fileId]?.status;
    // The bug: this comes back completed. Correct behavior: NOT completed.
    expect(fileStatus, isNot(TransferStatus.completed),
        reason: 'short upload was accepted as complete (status=$status)');
  });

  test('negative and past-end offset are rejected with 400', () async {
    final saveDir = await Directory.systemTemp.createTemp('ll_bad_offset_test');
    final receiver = Receiver(
      localDeviceProvider: () => device('rx', receiverFp, 0).copyWith(),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept({for (final f in files) f.id}),
      onSessionStarted: (_) {},
      certificateProvider: testCertificateProvider,
    );
    await receiver.start();
    addTearDown(() async {
      await receiver.stop();
      await saveDir.delete(recursive: true);
    });
    final port = receiver.port!;
    final dio = trustAllDio();
    final fileId = uuid.v4();
    final prep = await dio.postUri<Map<String, dynamic>>(
      Uri(
          scheme: 'https',
          host: '127.0.0.1',
          port: port,
          path: LanLinkProtocol.routePrepareUpload),
      data: {
        'info': device('tx', 'txfp', 0).toJson(),
        'files': {
          fileId: FileInfo(
                  id: fileId, fileName: 'x.bin', size: 100, fileType: 'other')
              .toJson(),
        },
      },
      options: Options(responseType: ResponseType.json),
    );
    final token = (prep.data!['files'] as Map)[fileId] as String;
    for (final bad in ['-5', '1000000']) {
      final resp = await dio.postUri<dynamic>(
        Uri(
            scheme: 'https',
            host: '127.0.0.1',
            port: port,
            path: LanLinkProtocol.routeUpload,
            queryParameters: {
              'sessionId': prep.data!['sessionId'],
              'fileId': fileId,
              'token': token,
              'offset': bad,
            }),
        data: Stream.fromIterable([List<int>.filled(10, 1)]),
        options: Options(
          contentType: 'application/octet-stream',
          headers: {HttpHeaders.contentLengthHeader: '10'},
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      expect(resp.statusCode, 400, reason: 'offset=$bad should be 400');
    }
  });
}
