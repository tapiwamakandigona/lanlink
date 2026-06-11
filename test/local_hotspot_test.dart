import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/local_hotspot.dart';

void main() {
  group('HotspotInfo.toWifiQrString', () {
    test('encodes plain credentials', () {
      const info = HotspotInfo(
        ssid: 'AndroidShare_1234',
        password: 'p4ssw0rd',
        hostIps: ['192.168.43.1'],
      );
      expect(
        info.toWifiQrString(),
        'WIFI:T:WPA;S:AndroidShare_1234;P:p4ssw0rd;;',
      );
    });

    test('escapes the special characters from the Wi-Fi QR spec', () {
      const info = HotspotInfo(
        ssid: 'my;net:wo,rk"x',
        password: r'pa\ss;word',
        hostIps: [],
      );
      expect(
        info.toWifiQrString(),
        r'WIFI:T:WPA;S:my\;net\:wo\,rk\"x;P:pa\\ss\;word;;',
      );
    });
  });
}
