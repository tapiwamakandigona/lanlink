import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/pair_payload.dart';

void main() {
  group('PairPayload', () {
    test('round-trips IP / port / alias / fingerprint', () {
      const original = PairPayload(
        ip: '192.168.1.42',
        port: 53317,
        alias: 'Tapiwa\'s phone',
        fingerprint: 'abcd1234',
      );
      final qr = original.toQrString();
      final parsed = PairPayload.tryParse(qr);
      expect(parsed, isNotNull);
      expect(parsed!.ip, original.ip);
      expect(parsed.port, original.port);
      expect(parsed.alias, original.alias);
      expect(parsed.fingerprint, original.fingerprint);
    });

    test('omits the fingerprint field when null', () {
      const p = PairPayload(ip: '10.0.0.5', port: 1234, alias: 'pc');
      expect(p.toQrString().contains('fp='), isFalse);
      final parsed = PairPayload.tryParse(p.toQrString());
      expect(parsed?.fingerprint, isNull);
    });

    test('rejects non-LanLink URIs', () {
      expect(PairPayload.tryParse('https://example.com'), isNull);
      expect(PairPayload.tryParse('lanlink://something-else'), isNull);
      expect(PairPayload.tryParse('not a uri at all'), isNull);
      expect(PairPayload.tryParse(''), isNull);
    });

    test('rejects pair URIs missing required fields', () {
      // Missing port
      expect(
        PairPayload.tryParse('lanlink://pair?ip=1.2.3.4&alias=x'),
        isNull,
      );
      // Missing ip
      expect(
        PairPayload.tryParse('lanlink://pair?port=53317&alias=x'),
        isNull,
      );
      // Missing alias
      expect(
        PairPayload.tryParse('lanlink://pair?ip=1.2.3.4&port=53317'),
        isNull,
      );
      // Out-of-range port
      expect(
        PairPayload.tryParse('lanlink://pair?ip=1.2.3.4&port=99999&alias=x'),
        isNull,
      );
    });

    test('round-trips hotspot credentials for the Direct link flow', () {
      const original = PairPayload(
        ip: '192.168.49.1',
        port: 53317,
        alias: 'Pixel',
        fingerprint: 'fp',
        ssid: 'AndroidShare_1234',
        password: 'p4ss w0rd&=',
      );
      final parsed = PairPayload.tryParse(original.toQrString());
      expect(parsed, isNotNull);
      expect(parsed!.ssid, original.ssid);
      expect(parsed.password, original.password);
      expect(parsed.needsHotspotJoin, isTrue);
    });

    test('backward compat: QRs without creds parse and need no join', () {
      // Exactly the pre-v4.1 wire shape.
      final parsed = PairPayload.tryParse(
        'lanlink://pair?ip=192.168.1.42&port=53317&alias=Pixel&fp=abcd',
      );
      expect(parsed, isNotNull);
      expect(parsed!.ssid, isNull);
      expect(parsed.password, isNull);
      expect(parsed.needsHotspotJoin, isFalse);
    });

    test('omits ssid/pass params when no credentials are set', () {
      const p = PairPayload(ip: '10.0.0.5', port: 1234, alias: 'pc');
      expect(p.toQrString().contains('ssid='), isFalse);
      expect(p.toQrString().contains('pass='), isFalse);
    });

    test('hostPort joins ip and port for legacy probe paths', () {
      const p = PairPayload(ip: '1.2.3.4', port: 1234, alias: 'x');
      expect(p.hostPort, '1.2.3.4:1234');
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
          PairPayload.tryParse(
            'lanlink://pair?ip=$ip&port=53317&alias=attacker',
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
          PairPayload.tryParse(
            'lanlink://pair?ip=$ip&port=53317&alias=peer',
          )?.ip,
          ip,
          reason: 'private QR target=$ip',
        );
      }
    });
  });
}
