// A peer-declared absurdly long filename used to pass prepare-upload and
// then kill the upload with ENAMETOOLONG — a 500 whose body leaked the
// receiver's local filesystem path. Now the name is clamped (with a hash
// suffix) and the transfer completes.
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import '../tls_test_helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('1000-char filename transfers with a clamped output name', () async {
    final saveDir = await Directory.systemTemp.createTemp('ll_longname');
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
    final fileId = uuid.v4();
    final longName = '${'a' * 1000}.bin';
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
                  id: fileId, fileName: longName, size: 10, fileType: 'other')
              .toJson(),
        },
      },
      options: Options(responseType: ResponseType.json),
    );
    final token = (prep.data!['files'] as Map)[fileId] as String;
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
      data: Stream.fromIterable([List<int>.filled(10, 1)]),
      options: Options(
        contentType: 'application/octet-stream',
        headers: {HttpHeaders.contentLengthHeader: '10'},
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    expect(resp.statusCode, 200);
    await waitFor(
        () => started?.files[fileId]?.status == TransferStatus.completed);
    final savedPath = started!.files[fileId]!.savedPath!;
    final savedName = savedPath.split(Platform.pathSeparator).last;
    // Clamped: fits a 255-byte filesystem limit with margin, keeps the
    // extension, and carries the disambiguating hash marker.
    expect(savedName.length, lessThanOrEqualTo(200));
    expect(savedName, endsWith('.bin'));
    expect(savedName, contains('~'));
    expect(File(savedPath).lengthSync(), 10);
  });
}
