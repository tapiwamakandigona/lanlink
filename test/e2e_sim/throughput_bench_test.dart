// Throughput benchmark on the REAL sender→receiver stack over loopback.
//
// Not a pass/fail perf gate (sandbox/CI hardware varies wildly) — it prints
// MB/s and files/s so perf work has evidence. Assertions only check
// correctness (all bytes arrive, hashes match).
//
// Run:  flutter test test/e2e_sim/throughput_bench_test.dart
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:dio/dio.dart';
import 'package:lanlink/core/transfer/sender.dart';

import 'e2e_helpers.dart';

/// Dio with [rtt] of artificial latency before every request — loopback has
/// ~0 RTT, so this is what makes the per-file round-trip cost (the thing
/// upload pipelining hides on real Wi-Fi) visible in a benchmark.
Dio delayedDio(Duration rtt) {
  final d = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 30),
    sendTimeout: const Duration(minutes: 30),
    responseType: ResponseType.json,
  ));
  d.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      await Future<void>.delayed(rtt);
      handler.next(options);
    },
  ));
  return d;
}

Future<void> main() async {
  late Directory tmp;
  late Directory saveDir;
  late Receiver receiver;
  late Sender sender;
  late Device receiverDevice;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lanlink_bench_');
    saveDir = await Directory('${tmp.path}/inbox').create();
    receiver = Receiver(
      localDeviceProvider: () => device('bench-rx', 'fp-rx', 53420),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept({for (final f in files) f.id}),
      onSessionStarted: (_) {},
    );
    await receiver.start();
    receiverDevice = device('bench-rx', 'fp-rx', receiver.port!);
    sender = Sender(localDeviceProvider: () => device('bench-tx', 'fp-tx', 1));
  });

  tearDown(() async {
    await receiver.stop();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('bench: one 300MB file', () async {
    const size = 300 * 1024 * 1024;
    final f = await writeDeterministicFile('${tmp.path}/big.bin', size);
    final info = fileInfoFor(f, fileName: 'big.bin', size: size);
    final session = sendSessionFor(receiverDevice, [info]);

    final sw = Stopwatch()..start();
    await sender.send(session: session, peer: receiverDevice, files: [info]);
    sw.stop();

    expect(session.status, TransferStatus.completed);
    final out = File('${saveDir.path}/big.bin');
    expect(await out.length(), size);
    expect(await sha256OfFile(out.path), await sha256OfFile(f.path));

    final mbs = size / 1024 / 1024 / (sw.elapsedMilliseconds / 1000);
    // ignore: avoid_print
    print('BENCH single-300MB: ${sw.elapsedMilliseconds} ms '
        '= ${mbs.toStringAsFixed(1)} MB/s');
  });

  test(
      'bench: 60 x 64KB files with 25ms simulated RTT, '
      'sequential vs pipelined', () async {
    const n = 60;
    const size = 64 * 1024;
    const rtt = Duration(milliseconds: 25);
    final files = <FileInfo>[];
    for (var i = 0; i < n; i++) {
      final f = await writeDeterministicFile('${tmp.path}/rtt_$i.bin', size,
          seed: i + 500);
      files.add(fileInfoFor(f, fileName: 'rtt_$i.bin', size: size));
    }

    Future<int> run(int parallel, String label) async {
      final s = Sender(
        localDeviceProvider: () => device('bench-tx', 'fp-tx', 1),
        dio: delayedDio(rtt),
        maxParallelUploads: parallel,
      );
      final session = sendSessionFor(receiverDevice, files);
      final sw = Stopwatch()..start();
      await s.send(session: session, peer: receiverDevice, files: files);
      sw.stop();
      expect(session.status, TransferStatus.completed,
          reason: '$label run must complete');
      return sw.elapsedMilliseconds;
    }

    // Fresh receiver save dirs per run so unique-name suffixing doesn't skew.
    final seq = await run(1, 'sequential');
    final pip = await run(3, 'pipelined');
    // ignore: avoid_print
    print('BENCH 60x64KB @25ms RTT: sequential=${seq}ms '
        'pipelined(3)=${pip}ms speedup=${(seq / pip).toStringAsFixed(2)}x');
    // The pipelined run must not be slower; the win comes from overlapping
    // the per-request latency. Generous bound to stay CI-safe.
    expect(pip, lessThan(seq));
  });

  test('bench: 200 x 256KB files', () async {
    const n = 200;
    const size = 256 * 1024;
    final files = <FileInfo>[];
    for (var i = 0; i < n; i++) {
      final f = await writeDeterministicFile('${tmp.path}/small_$i.bin', size,
          seed: i);
      files.add(fileInfoFor(f, fileName: 'small_$i.bin', size: size));
    }
    final session = sendSessionFor(receiverDevice, files);

    final sw = Stopwatch()..start();
    await sender.send(session: session, peer: receiverDevice, files: files);
    sw.stop();

    expect(session.status, TransferStatus.completed);
    var totalOut = 0;
    for (var i = 0; i < n; i++) {
      totalOut += await File('${saveDir.path}/small_$i.bin').length();
    }
    expect(totalOut, n * size);

    final fps = n / (sw.elapsedMilliseconds / 1000);
    // ignore: avoid_print
    print('BENCH 200x256KB: ${sw.elapsedMilliseconds} ms '
        '= ${fps.toStringAsFixed(1)} files/s');
  });
}
