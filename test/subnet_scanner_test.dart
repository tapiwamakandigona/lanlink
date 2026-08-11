import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/subnet_scanner.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<HttpServer> _spinUpFakePeer({
  required String alias,
  required String fingerprint,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(_serveInfo(server, alias, fingerprint));
  return server;
}

Future<void> _serveInfo(
  HttpServer server,
  String alias,
  String fingerprint,
) async {
  await for (final req in server) {
    if (req.uri.path.endsWith(LanLinkProtocol.routeInfo) &&
        req.method == 'GET') {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'alias': alias,
        'version': LanLinkProtocol.protocolVersion,
        'deviceModel': 'test',
        'deviceType': LanLinkProtocol.deviceTypeHeadless,
        'fingerprint': fingerprint,
        'port': server.port,
        'protocol': 'http',
      }));
      await req.response.close();
    } else {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    }
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'SubnetScanner picks up a peer answering /info on a loopback port and '
      'invokes onPeer with the discovered alias', () async {
    final fake = await _spinUpFakePeer(
      alias: 'unit-test-peer',
      fingerprint: 'abc123',
    );
    addTearDown(() => fake.close(force: true));

    final sender = Sender(
      localDeviceProvider: () => Device(
        alias: 'me',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'me',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'me',
        port: fake.port,
        protocol: 'http',
        ip: '127.0.0.1',
      ),
    );

    Device? seen;
    final scanner = SubnetScanner(
      sender: sender,
      onPeer: (peer) {
        seen ??= peer;
      },
      ports: [fake.port],
      perHostTimeout: const Duration(seconds: 2),
      parallelProbes: 8,
    );
    // We only need scanner to look at the 127.0.0.0/24 range, which it
    // derives from any IPv4 in the supplied list whose first three octets
    // match. We pass `127.0.0.0` so the /24 prefix `127.0.0` is included.
    await scanner.scan(localIps: ['127.0.0.0']);
    expect(seen, isNotNull);
    expect(seen!.alias, 'unit-test-peer');
    expect(seen!.fingerprint, 'abc123');
  });

  test('well-known hotspot prefixes cover the common OEM gateways', () {
    // Regression guard: these are the gateway /24s phones hand out. If one
    // is dropped, hotspot discovery silently regresses on that OEM.
    const prefixes = SubnetScanner.wellKnownHotspotPrefixes;
    expect(
        prefixes,
        containsAll(<String>{
          '192.168.43', // stock Android
          '192.168.49', // Wi-Fi Direct / legacy tethering
          '192.168.45', // Samsung
          '192.168.137', // Windows mobile hotspot
          '172.20.10', // iOS Personal Hotspot
        }));
  });
  test(
      'SubnetScanner finds a peer on a receiver fallback port '
      '(default+1) without being told', () async {
    // Reserve the "default" port with a dumb socket that never answers
    // /info, and park the fake peer on the next port up — the situation
    // after Receiver._bindWithFallback loses the default port to another
    // instance.
    final blocker = await ServerSocket.bind('127.0.0.1', 0);
    addTearDown(blocker.close);
    final fake = await _spinUpFakePeer(
      alias: 'fallback-peer',
      fingerprint: 'fp-fallback',
    );
    addTearDown(() => fake.close(force: true));

    final sender = Sender(
      localDeviceProvider: () => Device(
        alias: 'me',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'me',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'me',
        port: fake.port,
        protocol: 'http',
        ip: '127.0.0.1',
      ),
    );

    Device? seen;
    final scanner = SubnetScanner(
      sender: sender,
      onPeer: (peer) => seen ??= peer,
      // Simulate: default port answers nothing, peer sits on "default+1".
      ports: [blocker.port, fake.port],
      perHostTimeout: const Duration(seconds: 2),
      parallelProbes: 8,
    );

    await scanner.scan(localIps: ['127.0.0.1'], force: true);

    expect(seen, isNotNull,
        reason: 'peer on the fallback port must be discovered');
    expect(seen!.alias, 'fallback-peer');
    expect(seen!.port, fake.port);
  });

  test(
      'throttle: unforced scan within minScanInterval is a no-op, '
      'force bypasses it', () async {
    final sender = Sender(
      localDeviceProvider: () => Device(
        alias: 'me',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'me',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'me',
        port: 53317,
        protocol: 'http',
        ip: '127.0.0.1',
      ),
    );
    final scanner = SubnetScanner(
      sender: sender,
      onPeer: (_) {},
      // Empty localIps + no fallbacks reachable: sweep is instant.
      ports: const [1],
      perHostTimeout: const Duration(milliseconds: 50),
      parallelProbes: 4,
      minScanInterval: const Duration(minutes: 5),
    );

    await scanner.scan(localIps: const [], force: true);
    final first = scanner.lastScanStartedAt;
    expect(first, isNotNull);

    // Within the interval: unforced re-kick (the periodic UI cadence)
    // must not start a new sweep.
    await scanner.scan(localIps: const []);
    expect(scanner.lastScanStartedAt, first,
        reason: 'unforced scan inside minScanInterval must be skipped');

    // An explicit user refresh does start one.
    await scanner.scan(localIps: const [], force: true);
    expect(scanner.lastScanStartedAt!.isAfter(first!), isTrue,
        reason: 'force must bypass the throttle');
  });
}
