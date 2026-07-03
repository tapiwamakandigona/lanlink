// Regression test for C3: discovery announcements must always carry the
// receiver's *actual* bound port. The self device is read through a provider
// per announcement, so a receiver port-fallback after discovery was
// constructed is still announced correctly.

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/multicast_discovery.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/protocol/constants.dart';

void main() {
  test('announcement payload tracks the live receiver port', () {
    var boundPort = 53317;
    final discovery = MulticastDiscovery(
      selfDeviceProvider: () => Device(
        alias: 'me',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'test',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'me-fp',
        port: boundPort,
        protocol: 'http',
        ip: '',
      ),
      onPeer: (_) {},
    );

    expect(discovery.announcementJson()['port'], 53317);

    // Simulate the receiver falling back to another port after discovery
    // was constructed (the C3 bug: the old snapshot kept announcing 53317).
    boundPort = 53401;
    expect(discovery.announcementJson()['port'], 53401,
        reason: 'announcements must advertise the port the receiver '
            'actually listens on');
    expect(
        discovery.announcementJson()['announce'] ??
            discovery.announcementJson()['announcement'],
        isNotNull);
  });
}
