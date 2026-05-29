import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/onboarding/pairing_choice.dart';
import 'package:lanlink/core/util/pairing_guide.dart';

void main() {
  group('PairingChoice', () {
    test('encode + decode round-trip', () {
      const choice = PairingChoice(
        direction: TransferDirection.send,
        other: OtherDeviceKind.iphone,
      );
      final encoded = choice.encode();
      final decoded = PairingChoice.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.direction, TransferDirection.send);
      expect(decoded.other, OtherDeviceKind.iphone);
    });

    test('decode returns null for empty / malformed input', () {
      expect(PairingChoice.decode(null), isNull);
      expect(PairingChoice.decode(''), isNull);
      expect(PairingChoice.decode('not json'), isNull);
      expect(PairingChoice.decode('"a string"'), isNull);
    });

    test('decode tolerates unknown enum values by falling back', () {
      const raw = '{"direction":"bogus","other":"bogus"}';
      final decoded = PairingChoice.decode(raw);
      expect(decoded, isNotNull);
      // Defaults: send + notSure
      expect(decoded!.direction, TransferDirection.send);
      expect(decoded.other, OtherDeviceKind.notSure);
    });

    test('summary uses human-friendly device names', () {
      const choice = PairingChoice(
        direction: TransferDirection.receive,
        other: OtherDeviceKind.windows,
      );
      expect(choice.summary, 'Receiving from a Windows PC');
    });
  });
}
