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
