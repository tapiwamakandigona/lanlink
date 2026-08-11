// Second split: inside the receiver-side loss (45 -> 17 MB/s), how much is
//  C) shelf pipeline alone (drain body, no disk)
//  D) bare HttpServer + IOSink file writes with 8MB flush cadence (no shelf)
// Prints MB/s; assertions correctness-only.
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../tls_test_helpers.dart';

const _size = 200 * 1024 * 1024;

Stream<List<int>> _source(int chunkSize) async* {
  final chunk = Uint8List(chunkSize);
  var sent = 0;
  while (sent < _size) {
    yield chunk;
    sent += chunk.length;
  }
}

Future<double> _upload(int port, String path) async {
  final client = HttpClient()..badCertificateCallback = (c, h, p) => true;
  final req = await client.postUrl(Uri.parse('https://127.0.0.1:$port$path'));
  req.headers.contentType = ContentType.binary;
  req.contentLength = _size;
  final sw = Stopwatch()..start();
  await req.addStream(_source(256 * 1024));
  final resp = await req.close();
  await resp.drain<void>();
  sw.stop();
  expect(resp.statusCode, 200);
  client.close();
  return _size / 1024 / 1024 / (sw.elapsedMilliseconds / 1000);
}

Future<void> main() async {
  test('C: shelf drain only (no disk)', () async {
    final handler = shelf.Pipeline().addHandler((req) async {
      var n = 0;
      await for (final c in req.read()) {
        n += c.length;
      }
      return shelf.Response.ok('got $n');
    });
    final server = await shelf_io.serve(handler, '127.0.0.1', 0,
        securityContext: testCertificate().securityContext());
    final mbs = await _upload(server.port, '/drain');
    // ignore: avoid_print
    print('SPLIT-C shelf drain: ${mbs.toStringAsFixed(1)} MB/s');
    await server.close(force: true);
  });

  test('D: bare server + IOSink file writes, 8MB flush', () async {
    final tmp = await Directory.systemTemp.createTemp('lanlink_split2_');
    final server = await HttpServer.bindSecure(
        '127.0.0.1', 0, testCertificate().securityContext());
    final done = Completer<int>();
    server.listen((req) async {
      final sink = File('${tmp.path}/out.bin').openWrite();
      var n = 0;
      var unflushed = 0;
      await for (final c in req) {
        sink.add(c);
        n += c.length;
        unflushed += c.length;
        if (unflushed >= 8 * 1024 * 1024) {
          unflushed = 0;
          await sink.flush();
        }
      }
      await sink.close();
      req.response.statusCode = 200;
      await req.response.close();
      if (!done.isCompleted) done.complete(n);
    });
    final mbs = await _upload(server.port, '/write');
    expect(await done.future, _size);
    // ignore: avoid_print
    print('SPLIT-D bare+file8MBflush: ${mbs.toStringAsFixed(1)} MB/s');
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });
}
