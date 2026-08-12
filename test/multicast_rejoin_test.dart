// Regression test for BUG-12: multicast group joins were memoized by
// interface *name*. After a Wi-Fi off/on (or hotspot toggle) the interface
// comes back under the same name (wlan0) with the kernel-side group
// membership silently gone — the memo skipped the rejoin forever and
// multicast reception stayed dead until app restart. The fix removes the
// memo: every refresh re-attempts every interface (duplicate joins throw
// "address in use", which is swallowed).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/multicast_discovery.dart';
import 'package:lanlink/core/models/device.dart';

Device _self() => Device(
      alias: 'me',
      version: '2.1',
      deviceModel: 'test',
      deviceType: 'headless',
      fingerprint: 'me-fp',
      port: 53317,
      protocol: 'https',
      ip: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every refresh re-attempts joins on every interface (no memo)',
      () async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    if (interfaces.isEmpty) {
      markTestSkipped('no non-loopback IPv4 interfaces in this environment');
      return;
    }

    final discovery = MulticastDiscovery(
      selfDeviceProvider: _self,
      onPeer: (_) {},
    );
    await discovery.start();
    addTearDown(discovery.stop);

    final afterStart = discovery.joinAttempts;
    expect(afterStart, greaterThan(0),
        reason: 'start() must attempt a join per socket per interface');

    await discovery.refreshMulticastJoins();
    final afterSecond = discovery.joinAttempts;
    final second = afterSecond - afterStart;

    await discovery.refreshMulticastJoins();
    final third = discovery.joinAttempts - afterSecond;

    // Before the fix the second and third refreshes attempted 0 joins
    // (every interface name was already in the memo).
    expect(second, greaterThan(0),
        reason: 'a later refresh must re-attempt joins so an interface '
            'that bounced (same name, lost membership) gets rejoined');
    expect(third, second,
        reason: 'each refresh attempts the same full interface set');
  });
}
