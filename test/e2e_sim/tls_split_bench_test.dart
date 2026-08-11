// Where do the MB/s go? Split experiments over the same loopback TLS:
//  A) real Receiver <- raw HttpClient POST (no dio, in-memory source)
//  B) shelf-free HttpServer.bindSecure <- dio POST (in-memory source)
// Compare with throughput_bench (real Sender+dio -> real Receiver, file
// source) and raw-socket ceiling (~45 MB/s @256KB in this sandbox).
// Prints MB/s; assertions are correctness-only.
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/transfer/receiver.dart';

import '../tls_test_helpers.dart';
import 'e2e_helpers.dart';

const _size = 200 * 1024 * 1024;

Stream<List<int>> _source(int chunkSize) async* {
  final chunk = Uint8List(chunkSize);
  var sent = 0;
  while (sent < _size) {
    yield chunk;
    sent += chunk.length;
  }
}

Future<void> main() async {
  test('A: real Receiver, raw HttpClient upload (no dio, memory source)',
      () async {
    final tmp = await Directory.systemTemp.createTemp('lanlink_split_');
    final saveDir = await Directory('${tmp.path}/inbox').create();
    final receiver = Receiver(
      certificateProvider: testCertificateProvider,
      localDeviceProvider: () => device('rx', 'fp-rx', 53421),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept({for (final f in files) f.id}),
      onSessionStarted: (_) {},
    );
    await receiver.start();

    // Handshake via dio (control plane, cheap), upload via raw HttpClient.
    final dio = trustAllDio(BaseOptions(responseType: ResponseType.json));
    final info = FileInfo(
        id: 'f1',
        fileName: 'big.bin',
        size: _size,
        fileType: 'application/octet-stream');
    final prep = await dio.post<Map<String, dynamic>>(
      'https://127.0.0.1:${receiver.port}/api/localsend/v2/prepare-upload',
      data: {
        'info': device('tx', 'fp-tx', 1).toJson(),
        'files': {'f1': info.toJson()},
      },
    );
    final sessionId = prep.data!['sessionId'] as String;
    final token = (prep.data!['files'] as Map)['f1'] as String;

    final client = HttpClient()..badCertificateCallback = (c, h, p) => true;
    final req = await client.postUrl(
        Uri.parse('https://127.0.0.1:${receiver.port}/api/localsend/v2/upload'
            '?sessionId=$sessionId&fileId=f1&token=$token'));
    req.headers.contentType = ContentType.binary;
    req.contentLength = _size;
    final sw = Stopwatch()..start();
    await req.addStream(_source(256 * 1024));
    final resp = await req.close();
    await resp.drain<void>();
    sw.stop();
    expect(resp.statusCode, 200);
    final mbs = _size / 1024 / 1024 / (sw.elapsedMilliseconds / 1000);
    // ignore: avoid_print
    print('SPLIT-A receiver+rawHttpClient: ${mbs.toStringAsFixed(1)} MB/s');
    client.close();
    await receiver.stop();
    await tmp.delete(recursive: true);
  });

  test('B: bare HttpServer.bindSecure, dio upload (memory source)', () async {
    final cert = testCertificate();
    final server =
        await HttpServer.bindSecure('127.0.0.1', 0, cert.securityContext());
    final done = Completer<int>();
    server.listen((req) async {
      var n = 0;
      await for (final c in req) {
        n += c.length;
      }
      req.response.statusCode = 200;
      await req.response.close();
      if (!done.isCompleted) done.complete(n);
    });
    final dio = trustAllDio(BaseOptions(responseType: ResponseType.json));
    final sw = Stopwatch()..start();
    final resp = await dio.post<dynamic>(
      'https://127.0.0.1:${server.port}/upload',
      data: _source(256 * 1024),
      options: Options(
        headers: {Headers.contentLengthHeader: _size},
        contentType: 'application/octet-stream',
      ),
    );
    sw.stop();
    expect(resp.statusCode, 200);
    expect(await done.future, _size);
    final mbs = _size / 1024 / 1024 / (sw.elapsedMilliseconds / 1000);
    // ignore: avoid_print
    print('SPLIT-B dio+bareServer: ${mbs.toStringAsFixed(1)} MB/s');
    await server.close(force: true);
  });
}
