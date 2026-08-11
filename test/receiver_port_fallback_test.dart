// Regression test for the port-conflict crash: when the desired port is
// already taken (e.g. another LanLink or LocalSend instance on the same
// machine), the receiver must fall back to a nearby or ephemeral port
// instead of throwing an unhandled SocketException that blanks the UI.

import 'tls_test_helpers.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';

Receiver _buildReceiver(int desiredPort) {
  return Receiver(
    certificateProvider: testCertificateProvider,
    localDeviceProvider: () => Device(
      alias: 'fallback-test',
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: 'fallback-fp',
      port: desiredPort,
      protocol: 'https',
      ip: '127.0.0.1',
    ),
    saveDirProvider: () async => Directory.systemTemp,
    onAccept: (peer, files) async => AcceptDecision.reject(),
    onSessionStarted: (_) {},
  );
}

void main() {
  test('receiver falls back to another port when the desired one is taken',
      () async {
    // Occupy a port so the receiver's preferred bind fails.
    final blocker = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final blockedPort = blocker.port;

    final receiver = _buildReceiver(blockedPort);
    try {
      await receiver.start();
      expect(receiver.isRunning, isTrue);
      expect(receiver.port, isNotNull);
      expect(receiver.port, isNot(blockedPort));
    } finally {
      await receiver.stop();
      await blocker.close();
    }
  });

  test('receiver binds the desired port when it is free', () async {
    final receiver = _buildReceiver(0);
    try {
      await receiver.start();
      expect(receiver.isRunning, isTrue);
      expect(receiver.port, isNotNull);
    } finally {
      await receiver.stop();
    }
  });
}
