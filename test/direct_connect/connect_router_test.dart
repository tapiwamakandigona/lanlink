import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/platform/wifi_joiner.dart';
import 'package:lanlink/ui/v4/direct_connect/connect_router.dart';

ConnectPayload _payload({String? ssid, String? password}) => ConnectPayload(
      ip: '192.168.49.1',
      port: 53317,
      alias: 'Pixel',
      fingerprint: 'fp',
      token: 'tok',
      ssid: ssid,
      password: password,
    );

void main() {
  group('ConnectRouter.route', () {
    test('reachable peer goes direct — never joins the hotspot', () async {
      var joinCalls = 0;
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => true,
        joinHotspot: (ssid, pass) async {
          joinCalls++;
          return WifiJoinResult.connected;
        },
      );
      final route =
          await router.route(_payload(ssid: 'LanLink-AP', password: 'pw'));
      expect(route, ConnectRoute.direct);
      expect(joinCalls, 0, reason: 'reachable peers must not trigger a join');
    });

    test('unreachable + creds joins the hotspot', () async {
      final joined = <String>[];
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async {
          joined.add('$ssid/$pass');
          return WifiJoinResult.connected;
        },
      );
      final route =
          await router.route(_payload(ssid: 'LanLink-AP', password: 'pw'));
      expect(route, ConnectRoute.joinedHotspot);
      expect(joined, ['LanLink-AP/pw']);
    });

    test('unreachable + creds but join declined reports joinFailed', () async {
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.declinedOrUnavailable,
      );
      final route =
          await router.route(_payload(ssid: 'LanLink-AP', password: 'pw'));
      expect(route, ConnectRoute.joinFailed);
    });

    test('unreachable without creds is plain unreachable — no join call',
        () async {
      var joinCalls = 0;
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async {
          joinCalls++;
          return WifiJoinResult.connected;
        },
      );
      final route = await router.route(_payload());
      expect(route, ConnectRoute.unreachable);
      expect(joinCalls, 0);
    });

    test('probe gets the payload address and the ~1.5s default timeout',
        () async {
      String? probed;
      Duration? usedTimeout;
      final router = ConnectRouter(
        probe: (ip, port, timeout) async {
          probed = '$ip:$port';
          usedTimeout = timeout;
          return true;
        },
      );
      await router.route(_payload());
      expect(probed, '192.168.49.1:53317');
      expect(usedTimeout, const Duration(milliseconds: 1500));
    });

    test('tcpProbe returns false fast for a closed port', () async {
      final ok =
          await tcpProbe('127.0.0.1', 1, const Duration(milliseconds: 300));
      expect(ok, isFalse);
    });
  });

  group('ConnectRouter.decide', () {
    test('propagates the timeout reason on a failed join', () async {
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.timeout,
      );
      final decision =
          await router.decide(_payload(ssid: 'LanLink-AP', password: 'pw'));
      expect(decision.route, ConnectRoute.joinFailed);
      expect(decision.joinResult, WifiJoinResult.timeout);
    });

    test('propagates declined_or_unavailable on a failed join', () async {
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.declinedOrUnavailable,
      );
      final decision =
          await router.decide(_payload(ssid: 'LanLink-AP', password: 'pw'));
      expect(decision.route, ConnectRoute.joinFailed);
      expect(decision.joinResult, WifiJoinResult.declinedOrUnavailable);
    });

    test('successful join carries the connected result', () async {
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.connected,
      );
      final decision =
          await router.decide(_payload(ssid: 'LanLink-AP', password: 'pw'));
      expect(decision.route, ConnectRoute.joinedHotspot);
      expect(decision.joinResult, WifiJoinResult.connected);
    });

    test('probe-only routes carry no join result', () async {
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => true,
        joinHotspot: (ssid, pass) async => WifiJoinResult.connected,
      );
      final decision =
          await router.decide(_payload(ssid: 'LanLink-AP', password: 'pw'));
      expect(decision.route, ConnectRoute.direct);
      expect(decision.joinResult, isNull);
    });

    test('onJoinStart fires after the probe fails and before the join',
        () async {
      final order = <String>[];
      final router = ConnectRouter(
        probe: (ip, port, timeout) async {
          order.add('probe');
          return false;
        },
        joinHotspot: (ssid, pass) async {
          order.add('join');
          return WifiJoinResult.connected;
        },
      );
      await router.decide(
        _payload(ssid: 'LanLink-AP', password: 'pw'),
        onJoinStart: () => order.add('joinStart'),
      );
      expect(order, ['probe', 'joinStart', 'join']);
    });

    test('onJoinStart never fires when the peer is already reachable',
        () async {
      var started = false;
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => true,
        joinHotspot: (ssid, pass) async => WifiJoinResult.connected,
      );
      await router.decide(
        _payload(ssid: 'LanLink-AP', password: 'pw'),
        onJoinStart: () => started = true,
      );
      expect(started, isFalse);
    });
  });

  group('ConnectRouter.waitForReachable', () {
    test('resolves true as soon as a probe succeeds', () async {
      var attempts = 0;
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => ++attempts >= 3,
      );
      final ok = await router.waitForReachable(
        _payload(ssid: 'LanLink-AP', password: 'pw'),
        interval: const Duration(milliseconds: 5),
        overall: const Duration(seconds: 2),
      );
      expect(ok, isTrue);
      expect(attempts, 3);
    });

    test('gives up after the overall budget and resolves false', () async {
      var attempts = 0;
      final router = ConnectRouter(
        probe: (ip, port, timeout) async {
          attempts++;
          return false;
        },
      );
      final ok = await router.waitForReachable(
        _payload(ssid: 'LanLink-AP', password: 'pw'),
        interval: const Duration(milliseconds: 10),
        overall: const Duration(milliseconds: 45),
      );
      expect(ok, isFalse);
      expect(attempts, greaterThanOrEqualTo(2));
    });
  });
}
