// Regression test for C3: discovery announcements must always carry the
// receiver's *actual* bound port. The self device is read through a provider
// per announcement, so a receiver port-fallback after discovery was
// constructed is still announced correctly.

import 'package:fake_async/fake_async.dart';
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
  test(
      'register mechanism: fresh announcements get a reply, responses do not '
      '(inverted before 2026-08-11 — cost up to 5s of discovery latency and '
      'risked a UDP reply loop against LocalSend)', () {
    var port = 53317;
    final discovery = MulticastDiscovery(
      selfDeviceProvider: () => Device(
        alias: 'me',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'unit',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'fp-self',
        port: port,
        protocol: 'http',
        ip: '',
      ),
      onPeer: (_) {},
    );

    Device packet({required bool announce}) => Device(
          alias: 'them',
          version: LanLinkProtocol.protocolVersion,
          deviceModel: 'unit',
          deviceType: LanLinkProtocol.deviceTypeHeadless,
          fingerprint: 'fp-peer',
          port: 53317,
          protocol: 'http',
          ip: '192.168.1.2',
          announcement: announce,
        );

    expect(discovery.shouldReplyTo(packet(announce: true)), isTrue,
        reason: 'a fresh announcement must be answered immediately');
    expect(discovery.shouldReplyTo(packet(announce: false)), isFalse,
        reason: 'never reply to a response — reply loop');

    // And the reply itself must be marked as a response, not an announce.
    expect(discovery.responseJson()['announce'], isNot(true));
    expect(discovery.announcementJson()['announce'], isTrue);
  });

  test(
      'announces go to multicast AND limited broadcast (hotspots/APs that '
      'filter multicast still see us without waiting for the subnet sweep)',
      () {
    final discovery = MulticastDiscovery(
      selfDeviceProvider: () => Device(
        alias: 'me',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'unit',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'fp-self',
        port: 53317,
        protocol: 'http',
        ip: '',
      ),
      onPeer: (_) {},
    );

    final targets = discovery.announceTargets().map((a) => a.address).toList();
    expect(targets, contains(LanLinkProtocol.multicastGroup),
        reason: 'multicast group is the primary, spec-compliant path');
    expect(targets, contains('255.255.255.255'),
        reason: 'limited broadcast is the fallback for multicast-filtering '
            'networks');
    expect(targets.first, LanLinkProtocol.multicastGroup,
        reason: 'multicast stays first so spec-compliant peers see the '
            'canonical packet first');
  });

  test('poke() sends a burst: one announce now, follow-ups on burstDelays', () {
    fakeAsync((async) {
      final discovery = MulticastDiscovery(
        selfDeviceProvider: () => Device(
          alias: 'me',
          version: LanLinkProtocol.protocolVersion,
          deviceModel: 'test',
          deviceType: LanLinkProtocol.deviceTypeHeadless,
          fingerprint: 'me-fp',
          port: 53317,
          protocol: 'http',
          ip: '',
        ),
        onPeer: (_) {},
      );

      discovery.poke();
      expect(discovery.announcesSent, 1,
          reason: 'first announce fires immediately');

      async.elapse(const Duration(milliseconds: 500));
      expect(discovery.announcesSent, 2,
          reason: 'first follow-up covers a datagram lost to radio wake-up');

      async.elapse(const Duration(milliseconds: 900));
      expect(discovery.announcesSent, 3, reason: 'second follow-up at 1.2s');

      // Burst is bounded — nothing else fires later.
      async.elapse(const Duration(seconds: 10));
      expect(discovery.announcesSent, 3);
    });
  });

  test('burst delays stay well under the steady announce interval', () {
    for (final d in MulticastDiscovery.burstDelays) {
      expect(d < LanLinkProtocol.announceInterval, isTrue);
    }
  });
}
