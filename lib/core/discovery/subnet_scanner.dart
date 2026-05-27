import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../protocol/constants.dart';
import '../transfer/sender.dart';

/// Sweeps the local /24 subnet(s) we care about (typical phone-hotspot
/// gateways and our own current address ranges) looking for any device that
/// answers `/api/localsend/v2/info`. Anything that replies is plumbed through
/// the same [onPeer] callback the multicast discovery uses, so the UI doesn't
/// have to special-case it.
///
/// This is the workaround for phones whose hotspot mode silently drops UDP
/// multicast packets (most modern Androids). We still keep the multicast
/// announcer running — the sweep is an additional path, not a replacement.
class SubnetScanner {
  SubnetScanner({
    required this.sender,
    required this.onPeer,
    this.port = LanLinkProtocol.defaultPort,
    this.perHostTimeout = const Duration(seconds: 2),
    this.parallelProbes = 32,
  });

  final Sender sender;
  final void Function(Device peer) onPeer;
  final int port;
  final Duration perHostTimeout;
  final int parallelProbes;

  bool _running = false;
  int _generation = 0;

  bool get isRunning => _running;

  /// Synchronously bumps the generation so any in-flight scan stops as soon
  /// as the next host slot picks it up.
  void cancel() {
    _generation += 1;
    _running = false;
  }

  /// Scans every /24 derived from [localIps] plus the well-known Android
  /// hotspot subnets. Completes when either every host has been probed or
  /// [cancel] is called.
  Future<void> scan({required List<String> localIps}) async {
    final gen = ++_generation;
    _running = true;
    try {
      final subnets = _subnetsToScan(localIps);
      for (final subnet in subnets) {
        if (_generation != gen) return;
        await _scanSubnet(subnet, gen);
      }
    } finally {
      if (_generation == gen) _running = false;
    }
  }

  Set<String> _subnetsToScan(List<String> localIps) {
    final subnets = <String>{};
    for (final ip in localIps) {
      final parts = ip.split('.');
      if (parts.length != 4) continue;
      subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
    }
    // Common Android hotspot gateway subnets — guaranteed to be there even
    // when our own IP lookup returns something stale.
    subnets.add('192.168.43');
    subnets.add('192.168.49');
    return subnets;
  }

  Future<void> _scanSubnet(String prefix, int gen) async {
    final mySet = <String>{};
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          mySet.add(addr.address);
        }
      }
    } catch (_) {}

    final hostQueue = <int>[];
    for (var i = 1; i <= 254; i++) {
      hostQueue.add(i);
    }

    final futures = <Future<void>>[];
    var idx = 0;
    void launch() {
      if (idx >= hostQueue.length) return;
      if (_generation != gen) return;
      final hostByte = hostQueue[idx++];
      final ip = '$prefix.$hostByte';
      if (mySet.contains(ip)) {
        // Skip our own IPs — probing them is wasted work and the response
        // would be filtered out by the announcer anyway.
        launch();
        return;
      }
      final f = _probe(ip, gen);
      futures.add(f);
      f.whenComplete(launch);
    }

    for (var i = 0; i < parallelProbes; i++) {
      launch();
    }
    await Future.wait(futures);
  }

  Future<void> _probe(String ip, int gen) async {
    if (_generation != gen) return;
    final stub = Device(
      alias: ip,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: '',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: '',
      port: port,
      protocol: 'http',
      ip: ip,
    );
    try {
      final probed = await sender.probe(stub).timeout(perHostTimeout);
      if (_generation != gen) return;
      if (probed != null) {
        onPeer(probed);
      }
    } catch (e) {
      if (kDebugMode && e is! TimeoutException && e is! SocketException) {
        debugPrint('[scan] probe $ip failed: $e');
      }
    }
  }
}
