import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/wizard_gate.dart';

void main() {
  group('shouldShowPairingWizard', () {
    test('never mode is always false', () {
      expect(
        shouldShowPairingWizard(wizardMode: 'never', hasLastPairing: false),
        isFalse,
      );
      expect(
        shouldShowPairingWizard(wizardMode: 'never', hasLastPairing: true),
        isFalse,
      );
    });

    test('always mode is always true', () {
      expect(
        shouldShowPairingWizard(wizardMode: 'always', hasLastPairing: false),
        isTrue,
      );
      expect(
        shouldShowPairingWizard(wizardMode: 'always', hasLastPairing: true),
        isTrue,
      );
    });

    test('auto mode shows wizard until first pairing', () {
      expect(
        shouldShowPairingWizard(wizardMode: 'auto', hasLastPairing: false),
        isTrue,
      );
      expect(
        shouldShowPairingWizard(wizardMode: 'auto', hasLastPairing: true),
        isFalse,
      );
    });

    test('unknown mode falls back to auto', () {
      expect(
        shouldShowPairingWizard(wizardMode: 'banana', hasLastPairing: false),
        isTrue,
      );
      expect(
        shouldShowPairingWizard(wizardMode: 'banana', hasLastPairing: true),
        isFalse,
      );
    });
  });
}
