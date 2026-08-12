// Regression tests for BUG-11: `_scanSubnet` handed `Future.wait` a list
// that kept growing *after* wait had snapshotted it, so `scan()` returned
// once the first [parallelProbes] probes finished while the remaining ~220
// probes per subnet were still in flight. Consequences before the fix:
// subnet sweeps overlapped (stacking concurrency far past the cap),
// `isRunning` flipped false while probes were still dialing, and the
// minScanInterval throttle measured from a sweep that hadn't ended.

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/subnet_scanner.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/transfer/sender.dart';

/// Fake sender: every probe waits a beat and reports null (host silent),
/// while tracking live and peak concurrency.
class _CountingSender extends Sender {
  _CountingSender() : super(localDeviceProvider: _self);

  static Device _self() => Device(
        alias: 'me',
        version: '2.1',
        deviceModel: 'test',
        deviceType: 'headless',
        fingerprint: 'me-fp',
        port: 1,
        protocol: 'https',
        ip: '',
      );

  int inFlight = 0;
  int peak = 0;
  int total = 0;

  @override
  Future<Device?> probe(Device peer, {cancelToken, Duration? timeout}) async {
    inFlight += 1;
    total += 1;
    if (inFlight > peak) peak = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    inFlight -= 1;
    return null;
  }
}

void main() {
  test('scan() only returns after every probe has completed', () async {
    final sender = _CountingSender();
    final scanner = SubnetScanner(
      sender: sender,
      onPeer: (_) {},
      parallelProbes: 16,
    );

    await scanner.scan(
        localIps: const ['10.99.1.5']).timeout(const Duration(seconds: 60));

    expect(sender.inFlight, 0,
        reason: 'scan() returned with probes still in flight');
    expect(scanner.isRunning, isFalse);
    // 6 subnets swept (own /24 + 5 well-known hotspot prefixes) × 254 hosts,
    // minus any of our own addresses that happen to fall in those ranges.
    final subnets = 1 + SubnetScanner.wellKnownHotspotPrefixes.length;
    expect(sender.total, greaterThan((subnets - 1) * 254),
        reason: 'the sweep must cover every subnet, not just the first '
            'parallelProbes hosts of each');
    // _probe tries up to 3 ports per silent host, so the ceiling is 3x.
    expect(
        sender.total,
        lessThanOrEqualTo(
            subnets * 254 * SubnetScanner.defaultProbePorts.length));
  });

  test('probe concurrency never exceeds parallelProbes', () async {
    final sender = _CountingSender();
    final scanner = SubnetScanner(
      sender: sender,
      onPeer: (_) {},
      parallelProbes: 8,
    );

    await scanner.scan(
        localIps: const ['10.99.2.5']).timeout(const Duration(seconds: 60));

    expect(sender.peak, lessThanOrEqualTo(8),
        reason: 'concurrency cap must hold across the whole sweep '
            '(before the fix, overlapping subnets stacked pools)');
  });
}
