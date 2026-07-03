import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
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
          return true;
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
          return true;
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
        joinHotspot: (ssid, pass) async => false,
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
          return true;
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
}
