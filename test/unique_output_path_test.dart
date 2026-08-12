// Regression test: with pipelined parallel uploads, two same-named files
// used to both pass the on-disk existence check before either rename
// landed — the second silently overwrote the first. uniqueOutputPath must
// hand out distinct paths even when called concurrently, before any file
// exists on disk.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';

void main() {
  test('concurrent same-name requests get distinct paths (pipelining race)',
      () async {
    final dir = await Directory.systemTemp.createTemp('lanlink_unique');
    addTearDown(() => dir.delete(recursive: true));
    final receiver = Receiver(
      localDeviceProvider: () => Device(
        alias: 'r',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'test',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'r-fp',
        port: 0,
        protocol: 'http',
        ip: '127.0.0.1',
      ),
      saveDirProvider: () async => dir,
      onAccept: (peer, files) async => AcceptDecision.reject(),
      onSessionStarted: (_) {},
    );

    // Simulate three parallel uploads of files all named photo.jpg whose
    // renames have not happened yet (nothing exists on disk).
    final paths = await Future.wait([
      receiver.uniqueOutputPath(dir, 'photo.jpg'),
      receiver.uniqueOutputPath(dir, 'photo.jpg'),
      receiver.uniqueOutputPath(dir, 'photo.jpg'),
    ]);

    expect(paths.toSet().length, 3,
        reason: 'parallel uploads of same-named files must never collide: '
            '$paths');
  });

  test('existing file on disk still gets suffixed', () async {
    final dir = await Directory.systemTemp.createTemp('lanlink_unique2');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/doc.pdf').writeAsString('x');
    final receiver = Receiver(
      localDeviceProvider: () => Device(
        alias: 'r',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'test',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'r-fp',
        port: 0,
        protocol: 'http',
        ip: '127.0.0.1',
      ),
      saveDirProvider: () async => dir,
      onAccept: (peer, files) async => AcceptDecision.reject(),
      onSessionStarted: (_) {},
    );

    final path = await receiver.uniqueOutputPath(dir, 'doc.pdf');
    expect(path, endsWith('doc (1).pdf'));
  });
}