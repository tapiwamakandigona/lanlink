// Adversarial fuzz over the peer-controlled parsers. Every payload here is
// something a hostile or buggy peer (or a stray LocalSend fork) can put on
// the wire; none of it may throw or escape as an unhandled async error.
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/protocol/constants.dart';

void main() {
  group('Device.fromJson is total over hostile/malformed payloads', () {
    test('port as numeric String is parsed, not thrown', () {
      final d = Device.fromJson({'fingerprint': 'abc', 'port': '53317'},
          ip: '10.0.0.5');
      expect(d.port, 53317);
    });
    test('port as double is truncated to int', () {
      final d = Device.fromJson({'fingerprint': 'abc', 'port': 53317.0},
          ip: '10.0.0.5');
      expect(d.port, 53317);
    });
    test('port out of range falls back to default', () {
      for (final bad in [0, -1, 70000, 'abc', '', 99999.9]) {
        final d = Device.fromJson({'fingerprint': 'abc', 'port': bad},
            ip: '10.0.0.5');
        expect(d.port, LanLinkProtocol.defaultPort, reason: 'port=$bad');
      }
    });
    test('port missing uses default', () {
      final d = Device.fromJson({'fingerprint': 'abc'}, ip: '10.0.0.5');
      expect(d.port, LanLinkProtocol.defaultPort);
    });
    test('non-string alias/version/model degrade to defaults, no throw', () {
      final d = Device.fromJson({
        'alias': 123,
        'version': false,
        'deviceModel': [1, 2],
        'deviceType': {'x': 1},
        'fingerprint': 42, // wrong type -> empty fingerprint
        'port': 53317,
      }, ip: '10.0.0.5');
      expect(d.alias, 'Unknown device');
      expect(d.version, LanLinkProtocol.protocolVersion);
      expect(d.deviceModel, '');
      expect(d.deviceType, LanLinkProtocol.deviceTypeHeadless);
      expect(d.fingerprint, '');
    });
    test('fully empty object does not throw', () {
      final d = Device.fromJson(<String, dynamic>{}, ip: '10.0.0.5');
      expect(d.port, greaterThan(0));
      expect(d.alias, 'Unknown device');
    });
    test('hostile URI schemes cannot escape the LAN transport', () {
      for (final scheme in [
        'file',
        'data',
        'javascript',
        'ftp',
        'HTTP',
        ' https ',
      ]) {
        final d = Device.fromJson({
          'fingerprint': 'abc',
          'protocol': scheme,
        }, ip: '10.0.0.5');
        expect(
          d.protocol,
          anyOf('http', 'https'),
          reason: 'untrusted protocol=$scheme',
        );
      }
    });
  });
}
