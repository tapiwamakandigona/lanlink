import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
    required this.selfDevice,
    required this.onPeer,
  });

  /// The device payload to announce. Should not include the local IP.
  Device selfDevice;

  /// Called whenever a new (or refreshed) peer is observed.
  final void Function(Device peer) onPeer;

  final List<RawDatagramSocket> _sockets = [];
  Timer? _announceTimer;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    final group = InternetAddress(LanLinkProtocol.multicastGroup);
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

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
      for (final iface in interfaces) {
        try {
          socket.joinMulticast(group, iface);
        } catch (e) {
          // Some interfaces (e.g. VPN tunnels) refuse to join multicast.
          // Swallow and continue with the rest.
          if (kDebugMode) {
            debugPrint(
                '[discovery] joinMulticast skipped on ${iface.name}: $e');
          }
        }
      }
      _sockets.add(socket);
      _bindSocketHandlers(socket);
    } catch (e) {
      if (kDebugMode) debugPrint('[discovery] failed to bind socket: $e');
    }

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
  }

  /// Triggers an immediate announce. Useful after settings change.
  void poke() => _announce();

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

  void _announce() {
    final payload = utf8.encode(json.encode(
      Device(
        alias: selfDevice.alias,
        version: selfDevice.version,
        deviceModel: selfDevice.deviceModel,
        deviceType: selfDevice.deviceType,
        fingerprint: selfDevice.fingerprint,
        port: selfDevice.port,
        protocol: selfDevice.protocol,
        ip: '',
        announcement: true,
      ).toJson(),
    ));
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
    final payload = utf8.encode(json.encode(
      Device(
        alias: selfDevice.alias,
        version: selfDevice.version,
        deviceModel: selfDevice.deviceModel,
        deviceType: selfDevice.deviceType,
        fingerprint: selfDevice.fingerprint,
        port: selfDevice.port,
        protocol: selfDevice.protocol,
        ip: '',
        announcement: true,
      ).toJson(),
    ));
    for (final s in _sockets) {
      try {
        s.send(payload, addr, port);
      } catch (_) {}
    }
  }
}
