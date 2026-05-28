import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/util/pairing_guide.dart';

void main() {
  group('resolvePairingGuide', () {
    test('two desktops use plain Wi-Fi auto-discovery, no QR', () {
      final g = resolvePairingGuide(
        self: SelfPlatform.windows,
        direction: TransferDirection.send,
        other: OtherDeviceKind.mac,
      );
      expect(g.title.toLowerCase(), contains('wi-fi'));
      expect(g.steps, isNotEmpty);
      expect(
        g.steps.any((s) => s.toLowerCase().contains('same wi-fi')),
        isTrue,
      );
    });

    test('Android hosting hotspot gets host-side steps', () {
      final g = resolvePairingGuide(
        self: SelfPlatform.android,
        direction: TransferDirection.send,
        other: OtherDeviceKind.iphone,
      );
      expect(g.steps.first.toLowerCase(), contains('hotspot'));
      expect(g.tip, isNotNull);
    });

    test('iPhone sending to an Android joins the Android hotspot', () {
      final g = resolvePairingGuide(
        self: SelfPlatform.ios,
        direction: TransferDirection.send,
        other: OtherDeviceKind.android,
      );
      expect(
        g.steps.any((s) => s.toLowerCase().contains('join')),
        isTrue,
      );
    });

    test('two non-Android phones fall back to Personal Hotspot guidance', () {
      final g = resolvePairingGuide(
        self: SelfPlatform.ios,
        direction: TransferDirection.receive,
        other: OtherDeviceKind.iphone,
      );
      expect(
        g.steps.any((s) => s.toLowerCase().contains('personal hotspot')),
        isTrue,
      );
    });

    test('"not sure" gives a safe generic answer', () {
      final g = resolvePairingGuide(
        self: SelfPlatform.android,
        direction: TransferDirection.send,
        other: OtherDeviceKind.notSure,
      );
      expect(g.steps.length, greaterThanOrEqualTo(2));
      expect(g.tip, isNotNull);
    });
  });
}
