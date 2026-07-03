import 'dart:async';
import 'dart:io';

import '../../../core/discovery/connect_payload.dart';
import '../../../core/platform/wifi_joiner.dart';

/// What the guest should do after scanning a QR, decided by the smart
/// routing probe (PLAN F1): try the peer on the current network first;
/// only fall back to joining the host's hotspot when it's unreachable
/// AND the QR carries credentials.
enum ConnectRoute {
  /// Peer answered on the current network — connect directly (today's flow).
  direct,

  /// Peer was unreachable; we joined its hotspot — retry the connect now.
  joinedHotspot,

  /// Peer unreachable, QR had credentials, but the programmatic join
  /// failed (declined dialog, unsupported platform, timeout).
  joinFailed,

  /// Peer unreachable and the QR has no hotspot credentials — nothing
  /// smarter to do than today's "keep both screens on" error.
  unreachable,
}

/// TCP-level reachability probe: can we open a socket to `ip:port` within
/// [timeout]? Deliberately not an HTTP probe — no tokens are spent and no
/// fingerprints are pinned by merely checking reachability.
Future<bool> tcpProbe(String ip, int port, Duration timeout) async {
  try {
    final socket = await Socket.connect(ip, port, timeout: timeout);
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Decides the connect route for a scanned payload. Probe and join are
/// injectable so the decision logic is unit-testable without sockets or
/// platform channels.
class ConnectRouter {
  ConnectRouter({
    Future<bool> Function(String ip, int port, Duration timeout)? probe,
    Future<bool> Function(String ssid, String password)? joinHotspot,
    this.probeTimeout = const Duration(milliseconds: 1500),
  })  : _probe = probe ?? tcpProbe,
        _join = joinHotspot ?? WifiJoiner.join;

  final Future<bool> Function(String ip, int port, Duration timeout) _probe;
  final Future<bool> Function(String ssid, String password) _join;

  /// ~1.5 s: long enough for a sleepy Wi-Fi radio, short enough that the
  /// hotspot fallback still feels instant.
  final Duration probeTimeout;

  Future<ConnectRoute> route(ConnectPayload payload) async {
    if (await _probe(payload.ip, payload.port, probeTimeout)) {
      return ConnectRoute.direct;
    }
    if (!payload.needsHotspotJoin) return ConnectRoute.unreachable;
    final joined = await _join(payload.ssid!, payload.password ?? '');
    return joined ? ConnectRoute.joinedHotspot : ConnectRoute.joinFailed;
  }
}
