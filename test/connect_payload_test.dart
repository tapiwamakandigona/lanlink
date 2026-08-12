import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/discovery/pair_payload.dart';

void main() {
  group('ConnectPayload', () {
    test('round-trips the same-Wi-Fi shape', () {
      const p = ConnectPayload(
        ip: '192.168.1.42',
        port: 53317,
        alias: "Gogo's tablet",
        fingerprint: 'abcd1234',
      );
      final parsed = ConnectPayload.tryParse(p.toQrString());
      expect(parsed, isNotNull);
      expect(parsed!.ip, '192.168.1.42');
      expect(parsed.port, 53317);
      expect(parsed.alias, "Gogo's tablet");
      expect(parsed.fingerprint, 'abcd1234');
      expect(parsed.needsHotspotJoin, isFalse);
    });

    test('round-trips the hotspot shape with credentials', () {
      const p = ConnectPayload(
        ip: '192.168.49.1',
        port: 53317,
        alias: 'Pixel',
        ssid: 'AndroidShare_4821',
        password: 'p@ss w0rd;:',
      );
      final parsed = ConnectPayload.tryParse(p.toQrString());
      expect(parsed, isNotNull);
      expect(parsed!.needsHotspotJoin, isTrue);
      expect(parsed.ssid, 'AndroidShare_4821');
      expect(parsed.password, 'p@ss w0rd;:');
      expect(parsed.hostPort, '192.168.49.1:53317');
    });

    test('accepts legacy lanlink://pair codes', () {
      const pair = PairPayload(
        ip: '10.0.0.5',
        port: 53317,
        alias: 'Desktop',
        fingerprint: 'ff00',
      );
      final parsed = ConnectPayload.tryParse(pair.toQrString());
      expect(parsed, isNotNull);
      expect(parsed!.ip, '10.0.0.5');
      expect(parsed.alias, 'Desktop');
      expect(parsed.needsHotspotJoin, isFalse);
    });

    test('legacy pair codes carry hotspot creds through (v4.1 host QR)', () {
      const pair = PairPayload(
        ip: '192.168.49.1',
        port: 53317,
        alias: 'Pixel',
        fingerprint: 'ff00',
        ssid: 'AndroidShare_9',
        password: 'secret',
      );
      final parsed = ConnectPayload.tryParse(pair.toQrString());
      expect(parsed, isNotNull);
      expect(parsed!.needsHotspotJoin, isTrue);
      expect(parsed.ssid, 'AndroidShare_9');
      expect(parsed.password, 'secret');
    });

    test('rejects junk', () {
      expect(ConnectPayload.tryParse(''), isNull);
      expect(ConnectPayload.tryParse('https://example.com'), isNull);
      expect(ConnectPayload.tryParse('WIFI:T:WPA;S:x;P:y;;'), isNull);
      expect(
        ConnectPayload.tryParse('lanlink://connect?ip=&port=1&alias=x'),
        isNull,
      );
      expect(
        ConnectPayload.tryParse('lanlink://connect?ip=1.2.3.4&port=0&alias=x'),
        isNull,
      );
    });

    test('rejects non-IP and non-LAN targets from scanned QRs', () {
      for (final ip in [
        'example.com',
        'localhost',
        '127.0.0.1',
        '0.0.0.0',
        '8.8.8.8',
        '172.32.0.1',
        '169.254.1.2',
        '999.1.2.3',
      ]) {
        expect(
          ConnectPayload.tryParse(
            'lanlink://connect?ip=$ip&port=53317&alias=attacker',
          ),
          isNull,
          reason: 'QR target=$ip',
        );
      }
    });

    test('accepts every private IPv4 LAN range', () {
      for (final ip in [
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.49.1',
      ]) {
        expect(
          ConnectPayload.tryParse(
            'lanlink://connect?ip=$ip&port=53317&alias=peer',
          )?.ip,
          ip,
          reason: 'private QR target=$ip',
        );
      }
    });
  });
}
