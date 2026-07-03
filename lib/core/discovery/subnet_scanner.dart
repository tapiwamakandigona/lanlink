import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
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
    this.minScanInterval = const Duration(seconds: 20),
  });

  final Sender sender;
  final void Function(Device peer) onPeer;
  final int port;
  final Duration perHostTimeout;
  final int parallelProbes;

  /// Minimum spacing between full sweeps. Callers re-kick the scan on a
  /// short UI cadence (~6 s); each sweep sets up/tears down hundreds of
  /// sockets on the main isolate, so back-to-back sweeps compete with
  /// frame production. Calls inside this window are no-ops.
  final Duration minScanInterval;

  bool _running = false;
  int _generation = 0;
  DateTime? _lastScanStarted;
  bool _transfersActive = false;

  bool get isRunning => _running;

  /// While true, [scan] is a no-op. Pages/state that know a transfer is
  /// in flight set this so the 254-host probe churn never competes with
  /// transfer I/O and progress frames.
  set transfersActive(bool active) => _transfersActive = active;

  /// Dio cancel tokens for probes currently in flight, so [cancel] can
  /// abort their sockets instead of merely abandoning the futures.
  final Set<CancelToken> _activeProbes = {};

  /// Synchronously bumps the generation so any in-flight scan stops as soon
  /// as the next host slot picks it up, and aborts the probes already in
  /// flight so their sockets close now rather than at the connect timeout.
  void cancel() {
    _generation += 1;
    _running = false;
    for (final token in _activeProbes.toList()) {
      token.cancel('scan cancelled');
    }
    _activeProbes.clear();
  }

  /// Scans every /24 derived from [localIps] plus the well-known Android
  /// hotspot subnets. Completes when either every host has been probed or
  /// [cancel] is called.
  ///
  /// Skipped (returns immediately) while a transfer is active or when the
  /// previous sweep started less than [minScanInterval] ago, unless
  /// [force] is set (e.g. an explicit user refresh).
  Future<void> scan(
      {required List<String> localIps, bool force = false}) async {
    if (_transfersActive && !force) return;
    final now = DateTime.now();
    final last = _lastScanStarted;
    if (!force && last != null && now.difference(last) < minScanInterval) {
      return;
    }
    _lastScanStarted = now;
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

  /// Well-known /24 prefixes that OEM phone hotspots hand out. These are
  /// always swept in addition to whatever our own interfaces report, because
  /// some Androids drop multicast in hotspot mode and our own IP lookup can
  /// be stale right after toggling the hotspot.
  ///
  /// Sources: stock Android (`.43`), Wi-Fi Direct / legacy tethering
  /// (`.49`), Samsung (`.45`), iOS Personal Hotspot (`172.20.10`), and a
  /// handful of common router defaults so a regular-LAN scan also has a
  /// fallback when interface enumeration fails.
  static const Set<String> wellKnownHotspotPrefixes = {
    '192.168.43', // stock Android hotspot
    '192.168.49', // Wi-Fi Direct / legacy tethering
    '192.168.45', // Samsung hotspot
    '192.168.137', // Windows mobile hotspot (ICS)
    '172.20.10', // iOS Personal Hotspot
  };

  Set<String> _subnetsToScan(List<String> localIps) {
    final subnets = <String>{};
    for (final ip in localIps) {
      final parts = ip.split('.');
      if (parts.length != 4) continue;
      subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
    }
    subnets.addAll(wellKnownHotspotPrefixes);
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
    // A per-probe cancel token: `.timeout` alone abandons the future but
    // the socket keeps dialing for the full dio connect timeout (10 s),
    // piling up ~160 lingering sockets on a dead subnet. Cancelling the
    // token on timeout (or an external [cancel]) closes the socket now.
    // Passing [perHostTimeout] down also aligns the receive budget with
    // this probe's deadline.
    final cancelToken = CancelToken();
    _activeProbes.add(cancelToken);
    try {
      final probed = await sender
          .probe(stub, cancelToken: cancelToken, timeout: perHostTimeout)
          .timeout(perHostTimeout);
      if (_generation != gen) return;
      if (probed != null) {
        onPeer(probed);
      }
    } catch (e) {
      if (e is TimeoutException && !cancelToken.isCancelled) {
        cancelToken.cancel('probe timeout');
      }
      if (kDebugMode && e is! TimeoutException && e is! SocketException) {
        debugPrint('[scan] probe $ip failed: $e');
      }
    } finally {
      _activeProbes.remove(cancelToken);
    }
  }
}
