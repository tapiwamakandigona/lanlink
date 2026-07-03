// E2E scenario 2 — ~150MB transfer between two real peer instances over
// loopback. Verifies:
//   * the received file is sha256-identical to the source,
//   * the transfer streams: peak RSS growth during the transfer stays far
//     below the file size (no full-file buffering on either side).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:path/path.dart' as p;

import 'e2e_helpers.dart';

void main() {
  test('150MB file streams end-to-end, hash-identical, no memory blowup',
      () async {
    final tmpRoot = await Directory.systemTemp.createTemp('lanlink_e2e_big_');
    final saveDir = Directory(p.join(tmpRoot.path, 'save'));
    await saveDir.create(recursive: true);
    TransferSession? receiveSession;

    final receiver = Receiver(
      localDeviceProvider: () => device('peer-a-receiver', 'fp-a', 0),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: (s) => receiveSession = s,
    );
    await receiver.start();
    final port = receiver.port!;
    final sender =
        Sender(localDeviceProvider: () => device('peer-b-sender', 'fp-b', 1));

    try {
      const size = 150 * 1024 * 1024; // 150 MB
      final src = await writeDeterministicFile(
          p.join(tmpRoot.path, 'big.bin'), size,
          seed: 99);
      final srcHash = await sha256OfFile(src.path);

      final info = fileInfoFor(src, fileName: 'big.bin', size: size);
      final peer = device('peer-a-receiver', 'fp-a', port);
      final session = sendSessionFor(peer, [info]);

      // Sample RSS every 50ms while the transfer runs. Both sender and
      // receiver live in this one process, so the peak covers both sides.
      final rssBefore = ProcessInfo.currentRss;
      var rssPeak = rssBefore;
      final sampler = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final rss = ProcessInfo.currentRss;
        if (rss > rssPeak) rssPeak = rss;
      });

      final sw = Stopwatch()..start();
      await sender.send(session: session, peer: peer, files: [info]);
      sw.stop();
      sampler.cancel();

      expect(session.status, TransferStatus.completed);
      expect(session.transferredBytes, size);
      expect(receiveSession, isNotNull);
      expect(receiveSession!.status, TransferStatus.completed);

      final savedPath = receiveSession!.files.values.single.savedPath!;
      expect(await File(savedPath).length(), size);
      expect(await sha256OfFile(savedPath), srcHash,
          reason: '150MB file must be byte-identical after transfer');

      final peakGrowthMb = (rssPeak - rssBefore) / (1024 * 1024);
      // ignore: avoid_print
      print('150MB transfer: ${sw.elapsedMilliseconds}ms, '
          'RSS before=${rssBefore ~/ (1024 * 1024)}MB '
          'peak growth=${peakGrowthMb.toStringAsFixed(1)}MB');
      // A non-streaming implementation would buffer >=150MB on at least one
      // side (often 300MB for both). Allow generous slack for GC noise and
      // socket buffers, but stay clearly below one full file size.
      expect(peakGrowthMb, lessThan(120),
          reason: 'peak RSS growth must stay far below the 150MB file size — '
              'the transfer must stream, not buffer');
    } finally {
      await receiver.stop();
      try {
        await tmpRoot.delete(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
