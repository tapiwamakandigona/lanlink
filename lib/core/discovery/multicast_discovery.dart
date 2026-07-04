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
    await _joinGroupOnCurrentInterfaces();

    // Send the first announce immediately, then on a timer.
    _announce();
    _announceTimer = Timer.periodic(
      LanLinkProtocol.announceInterval,
      (_) => _announce(),
    );
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    for (final s in _sockets) {
      try {
        s.close();
      } catch (_) {}
    }
    _sockets.clear();
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

  /// Triggers an immediate announce. Useful after settings change.
  ///
  /// Also re-joins the multicast group on the *current* interface set:
  /// interfaces that appeared after [start] (e.g. the hotspot interface
  /// once this phone joins the PC-hosted network) would otherwise never
  /// receive group traffic. Cheap — one interface enumeration; re-joining
  /// an already-joined interface just throws and is swallowed like at
  /// start.
  void poke() {
    unawaited(_joinGroupOnCurrentInterfaces());
    _announce();
  }

  /// Joins the multicast group on every currently present IPv4 interface.
  /// Called at [start] and again on every [poke] so late-appearing
  /// interfaces are picked up.
  Future<void> _joinGroupOnCurrentInterfaces() async {
    if (!_running || _sockets.isEmpty) return;
    final group = InternetAddress(LanLinkProtocol.multicastGroup);
    final List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
    } catch (_) {
      return;
    }
    for (final socket in _sockets) {
      for (final iface in interfaces) {
        try {
          socket.joinMulticast(group, iface);
        } catch (e) {
          // Some interfaces (e.g. VPN tunnels) refuse to join multicast,
          // and already-joined interfaces throw "address in use". Swallow
          // and continue with the rest.
          if (kDebugMode) {
            debugPrint(
                '[discovery] joinMulticast skipped on ${iface.name}: $e');
          }
        }
      }
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
    final fingerprint = payload['fingerprint'] as String?;
    if (fingerprint == null || fingerprint.isEmpty) return;
    // Ignore our own announce.
    if (fingerprint == selfDevice.fingerprint) {
      return;
    }
    final peer = Device.fromJson(payload, ip: fromIp);
    onPeer(peer);

    // If the peer didn't explicitly announce ("register" style), send them
    // our own announce so they discover us too.
    if (peer.announcement == false) {
      _sendAnnounceTo(datagram.address, datagram.port);
    }
  }

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

  void _announce() {
    final payload = utf8.encode(json.encode(announcementJson()));
    for (final s in _sockets) {
      try {
        s.send(
          payload,
          InternetAddress(LanLinkProtocol.multicastGroup),
          LanLinkProtocol.discoveryPort,
        );
      } catch (_) {}
    }
  }

  void _sendAnnounceTo(InternetAddress addr, int port) {
    final payload = utf8.encode(json.encode(announcementJson()));
    for (final s in _sockets) {
      try {
        s.send(payload, addr, port);
      } catch (_) {}
    }
  }
}
