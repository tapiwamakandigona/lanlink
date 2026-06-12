import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/onboarding_gate.dart';

void main() {
  group('shouldShowOnboarding', () {
    test('first run (never onboarded) shows the tour', () {
      expect(
        shouldShowOnboarding(lastOnboardedVersion: '', currentVersion: '3.1.0'),
        isTrue,
      );
    });

    test('whitespace-only marker counts as never onboarded', () {
      expect(
        shouldShowOnboarding(
            lastOnboardedVersion: '   ', currentVersion: '3.1.0'),
        isTrue,
      );
    });

    test('same version does not re-show', () {
      expect(
        shouldShowOnboarding(
            lastOnboardedVersion: '3.1.0', currentVersion: '3.1.0'),
        isFalse,
      );
    });

    test('older onboarded version re-shows after an update', () {
      expect(
        shouldShowOnboarding(
            lastOnboardedVersion: '3.0.0', currentVersion: '3.1.0'),
        isTrue,
      );
    });
  });

  group('isFirstRun', () {
    test('empty marker is a first run', () {
      expect(isFirstRun(lastOnboardedVersion: ''), isTrue);
    });

    test('whitespace-only marker is a first run', () {
      expect(isFirstRun(lastOnboardedVersion: '   '), isTrue);
    });

    test('any recorded version means not a first run', () {
      expect(isFirstRun(lastOnboardedVersion: '3.4.0'), isFalse);
    });
  });
}
