// Failed/abandoned transfers leave .part files in .lanlink_parts as resume
// head starts. Without pruning they accumulate forever and silently eat
// disk. Receiver.prunePartFiles removes parts older than partFileTtl and
// keeps fresh ones.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';

void main() {
  test('stale parts are deleted, fresh parts survive', () async {
    final dir = await Directory.systemTemp.createTemp('lanlink_parts');
    addTearDown(() => dir.delete(recursive: true));
    final partsDir = Directory('${dir.path}/.lanlink_parts');
    await partsDir.create(recursive: true);

    final stale = File('${partsDir.path}/old.bin.100.part');
    await stale.writeAsString('x' * 10);
    await stale
        .setLastModified(DateTime.now().subtract(Receiver.partFileTtl * 2));

    final fresh = File('${partsDir.path}/new.bin.100.part');
    await fresh.writeAsString('y' * 10);

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

    await receiver.prunePartFiles(dir);

    expect(await stale.exists(), isFalse,
        reason: 'a part older than partFileTtl is dead weight');
    expect(await fresh.exists(), isTrue,
        reason: 'a fresh part is the resume head start for a retry');
  });

  test('no parts dir -> no-op', () async {
    final dir = await Directory.systemTemp.createTemp('lanlink_noparts');
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
    await receiver.prunePartFiles(dir); // must not throw
  });
}
