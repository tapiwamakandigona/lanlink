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

    test('hostPort joins ip and port for legacy probe paths', () {
      const p = PairPayload(ip: '1.2.3.4', port: 1234, alias: 'x');
      expect(p.hostPort, '1.2.3.4:1234');
    });
  });
}
