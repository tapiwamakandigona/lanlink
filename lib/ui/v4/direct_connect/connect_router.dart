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

/// A [ConnectRoute] plus, when a programmatic join ran, its outcome — so
/// the UI can tell a timed-out dialog from a declined one and drive the
/// Tier-2/3 fallback with the right wording.
class RouteDecision {
  const RouteDecision(this.route, {this.joinResult});

  final ConnectRoute route;

  /// Set only when a join was attempted ([ConnectRoute.joinedHotspot] or
  /// [ConnectRoute.joinFailed]); null for probe-only routes.
  final WifiJoinResult? joinResult;
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
    Future<WifiJoinResult> Function(String ssid, String password)? joinHotspot,
    this.probeTimeout = const Duration(milliseconds: 1500),
  })  : _probe = probe ?? tcpProbe,
        _join = joinHotspot ?? WifiJoiner.join;

  final Future<bool> Function(String ip, int port, Duration timeout) _probe;
  final Future<WifiJoinResult> Function(String ssid, String password) _join;

  /// ~1.5 s: long enough for a sleepy Wi-Fi radio, short enough that the
  /// hotspot fallback still feels instant.
  final Duration probeTimeout;

  /// Full decision including the join outcome. [onJoinStart] fires just
  /// before the programmatic join begins (after the probe has failed), so
  /// the UI can switch to "a system dialog is about to appear" guidance.
  Future<RouteDecision> decide(
    ConnectPayload payload, {
    void Function()? onJoinStart,
  }) async {
    if (await _probe(payload.ip, payload.port, probeTimeout)) {
      return const RouteDecision(ConnectRoute.direct);
    }
    if (!payload.needsHotspotJoin) {
      return const RouteDecision(ConnectRoute.unreachable);
    }
    onJoinStart?.call();
    final result = await _join(payload.ssid!, payload.password ?? '');
    return RouteDecision(
      result.joined ? ConnectRoute.joinedHotspot : ConnectRoute.joinFailed,
      joinResult: result,
    );
  }

  /// Backward-compatible shorthand for callers that only need the route.
  Future<ConnectRoute> route(ConnectPayload payload) async =>
      (await decide(payload)).route;

  /// Tier-2/3 follow-up: polls the payload's `ip:port` every [interval]
  /// for up to [overall], resolving true as soon as the peer answers —
  /// used while the user joins the network via the Settings panel or by
  /// hand, so the connect flow can resume automatically.
  ///
  /// [isCancelled] makes the loop abortable (user cancel, page dispose):
  /// checked before every probe and every sleep; a cancelled wait resolves
  /// false without opening further sockets.
  Future<bool> waitForReachable(
    ConnectPayload payload, {
    Duration interval = const Duration(seconds: 2),
    Duration overall = const Duration(seconds: 90),
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    final deadline = DateTime.now().add(overall);
    while (true) {
      if (cancelled()) return false;
      if (await _probe(payload.ip, payload.port, probeTimeout)) return true;
      if (cancelled()) return false;
      if (!DateTime.now().add(interval).isBefore(deadline)) return false;
      await Future<void>.delayed(interval);
    }
  }
}
