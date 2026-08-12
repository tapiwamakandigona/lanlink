import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../protocol/constants.dart';

/// Maintains a UDP-multicast presence on the LAN and listens for peers.
///
/// Every [LanLinkProtocol.announceInterval] we send a JSON payload describing
/// ourselves to `224.0.0.167:53317`. Every peer that does the same is parsed,
/// stamped with the source IP, and pushed to [peers].
///
/// We also listen for unicast announcements so that newly joined devices can
/// "wake up" peers that have already announced (LocalSend's "register"
/// mechanism — we respond to any inbound packet with our own announcement).
class MulticastDiscovery {
  MulticastDiscovery({
    required this.selfDeviceProvider,
    required this.onPeer,
  });

  /// Returns the device payload to announce (should not include the local
  /// IP). A provider — rather than a snapshot — so every announcement
  /// carries the receiver's *actual* bound port even when the HTTP server
  /// fell back to a different port after this object was constructed, and
  /// so settings changes (alias etc.) take effect immediately.
  final Device Function() selfDeviceProvider;

  /// The current self-device payload, freshly built from the provider.
  Device get selfDevice => selfDeviceProvider();

  /// Called whenever a new (or refreshed) peer is observed.
  final void Function(Device peer) onPeer;

  final List<RawDatagramSocket> _sockets = [];
  Timer? _announceTimer;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    // Bind one socket to ANY and join the multicast group on each iface.
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        LanLinkProtocol.discoveryPort,
        reuseAddress: true,
        reusePort: false,
      );
      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;
      _sockets.add(socket);
      _bindSocketHandlers(socket);
    } catch (e) {
      if (kDebugMode) debugPrint('[discovery] failed to bind socket: $e');
    }
    // Android Wi-Fi drivers filter inbound multicast unless the app holds
    // a MulticastLock (the manifest permission alone does nothing). Without
    // it, peer announcements never arrive and discovery silently degrades
    // to subnet scans only.
    await _setMulticastLock(true);
    await _refreshMulticastJoins();

    // Send the first announces as a short burst, then steady on a timer.
    // Every few ticks, re-join the multicast group on any newly appeared
    // interface (hotspot toggled on, Wi-Fi reconnected, VPN dropped) — a
    // socket only receives group traffic on interfaces it joined, and the
    // set at bind time goes stale on mobile.
    _announceBurst();
    var tick = 0;
    _announceTimer = Timer.periodic(
      LanLinkProtocol.announceInterval,
      (_) {
        tick += 1;
        if (tick % _rejoinEveryTicks == 0) {
          unawaited(_refreshMulticastJoins());
        }
        _announce();
      },
    );
  }

  /// Re-joins the multicast group on every interface not yet joined.
  /// Cheap (one interface listing); called at start, periodically, and on
  /// [poke] so interfaces that appear after startup (the hotspot interface,
  /// a reconnected Wi-Fi) still receive group traffic.
  static const _rejoinEveryTicks = 6; // every ~30s with a 5s interval
  final Set<String> _joinedInterfaces = {};

  Future<void> _refreshMulticastJoins() async {
    if (!_running || _sockets.isEmpty) return;
    final group = InternetAddress(LanLinkProtocol.multicastGroup);
    List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
    } catch (_) {
      return;
    }
    if (!_running) return;
    for (final socket in _sockets) {
      for (final iface in interfaces) {
        if (_joinedInterfaces.contains(iface.name)) continue;
        try {
          socket.joinMulticast(group, iface);
          _joinedInterfaces.add(iface.name);
        } catch (e) {
          // Some interfaces (e.g. VPN tunnels) refuse to join multicast,
          // and already-joined interfaces throw "address in use". Swallow
          // and continue with the rest; retry next refresh.
          if (kDebugMode) {
            debugPrint(
                '[discovery] joinMulticast skipped on ${iface.name}: $e');
          }
        }
      }
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    for (final t in _burstTimers) {
      t.cancel();
    }
    _burstTimers.clear();
    for (final s in _sockets) {
      try {
        s.close();
      } catch (_) {}
    }
    _sockets.clear();
    _joinedInterfaces.clear();
    await _setMulticastLock(false);
  }

  /// Acquires/releases the Android multicast lock via the `lanlink/wifi`
  /// channel. A no-op everywhere else (and under `flutter test`, where the
  /// channel is not wired).
  static const _wifiChannel = MethodChannel('lanlink/wifi');

  Future<void> _setMulticastLock(bool acquire) async {
    if (!Platform.isAndroid) return;
    try {
      await _wifiChannel.invokeMethod<bool>(
        acquire ? 'acquireMulticastLock' : 'releaseMulticastLock',
      );
    } catch (_) {
      // Best-effort: discovery still works via subnet scans without it.
    }
  }

  /// Triggers an immediate announce burst. Useful after settings change.
  ///
  /// Also re-joins the multicast group on the *current* interface set:
  /// interfaces that appeared after [start] (e.g. the hotspot interface
  /// once this phone joins the PC-hosted network) would otherwise never
  /// receive group traffic.
  void poke() {
    unawaited(_refreshMulticastJoins());
    _announceBurst();
  }

  /// One announce now plus two quick follow-ups. A single UDP datagram is
  /// routinely lost right after a radio wakes from power-save (the classic
  /// "second scan finds it" bug); a 0/400ms/1200ms burst keeps
  /// time-to-first-peer near-instant without meaningfully raising chatter.
  /// Delays are test-visible via [burstDelays].
  static const burstDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];

  final List<Timer> _burstTimers = [];

  void _announceBurst() {
    _announce();
    _burstTimers.removeWhere((t) => !t.isActive);
    for (final delay in burstDelays) {
      _burstTimers.add(Timer(delay, _announce));
    }
  }

  void _bindSocketHandlers(RawDatagramSocket socket) {
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      _handleDatagram(datagram);
    });
  }

  void _handleDatagram(Datagram datagram) {
    final fromIp = datagram.address.address;
    String text;
    try {
      text = utf8.decode(datagram.data);
    } catch (_) {
      return;
    }
    Map<String, dynamic> payload;
    try {
      payload = json.decode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final fingerprint = payload['fingerprint'] is String
        ? payload['fingerprint'] as String
        : null;
    if (fingerprint == null || fingerprint.isEmpty) return;
    // Ignore our own announce.
    if (fingerprint == selfDevice.fingerprint) {
      return;
    }
    // Device.fromJson is total, but keep a guard here so any future field
    // parsing that can throw never escapes the socket listener as an
    // unhandled async error.
    final Device peer;
    try {
      peer = Device.fromJson(payload, ip: fromIp);
    } catch (_) {
      return;
    }
    onPeer(peer);

    // LocalSend register mechanism: a *fresh announcement* (announce=true)
    // gets a unicast response so the newcomer learns us immediately instead
    // of waiting up to announceInterval for our next periodic announce.
    // The response carries announce=false, which is exactly why we must
    // never reply to announce=false packets ourselves — replying to
    // responses ping-pongs forever against a spec-compliant LocalSend.
    //
    // (Until 2026-08-11 this condition was inverted: we ignored fresh
    // announcements — adding up to 5s of discovery latency — and replied
    // to responses instead.)
    if (shouldReplyTo(peer)) {
      _sendResponseTo(datagram.address, datagram.port);
    }
  }

  /// True when [peer]'s packet is a fresh announcement that deserves a
  /// unicast response (never respond to responses — loop risk).
  @visibleForTesting
  bool shouldReplyTo(Device peer) => peer.announcement;

  /// The JSON payload every announcement carries. Built fresh from
  /// [selfDeviceProvider] on each call so the announced port always matches
  /// the receiver's live bound port.
  @visibleForTesting
  Map<String, dynamic> announcementJson() {
    final self = selfDevice;
    return Device(
      alias: self.alias,
      version: self.version,
      deviceModel: self.deviceModel,
      deviceType: self.deviceType,
      fingerprint: self.fingerprint,
      port: self.port,
      protocol: self.protocol,
      ip: '',
      announcement: true,
    ).toJson();
  }

  /// Total announces attempted; lets tests observe burst behavior without
  /// real sockets.
  @visibleForTesting
  int announcesSent = 0;

  void _announce() {
    announcesSent += 1;
    final payload = utf8.encode(json.encode(announcementJson()));
    for (final s in _sockets) {
      for (final target in announceTargets()) {
        try {
          s.send(payload, target, LanLinkProtocol.discoveryPort);
        } catch (_) {}
      }
    }
  }

  /// Destinations every announce is sent to. Multicast is the primary,
  /// spec-compliant path, but many phone hotspots and consumer APs filter
  /// multicast (IGMP snooping without a querier) while still forwarding the
  /// limited broadcast address. Announcing to both costs one extra small
  /// datagram per interval and makes discovery work on those networks
  /// without waiting for the (slower, 20s-throttled) subnet sweep.
  /// Receivers dedupe naturally: same fingerprint, same [onPeer] refresh.
  @visibleForTesting
  List<InternetAddress> announceTargets() => [
        InternetAddress(LanLinkProtocol.multicastGroup),
        InternetAddress('255.255.255.255'),
      ];

  /// The unicast reply to a fresh announcement: same device payload but
  /// with `announce` unset (false), marking it a response per the LocalSend
  /// v2 discovery flow.
  @visibleForTesting
  Map<String, dynamic> responseJson() {
    final j = announcementJson();
    j.remove('announce');
    return j;
  }

  void _sendResponseTo(InternetAddress addr, int port) {
    final payload = utf8.encode(json.encode(responseJson()));
    for (final s in _sockets) {
      try {
        s.send(payload, addr, port);
      } catch (_) {}
    }
  }
}
