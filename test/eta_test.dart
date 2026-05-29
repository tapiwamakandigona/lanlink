import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/eta.dart';

void main() {
  group('plainEnglishEta', () {
    test('returns empty when speed is zero or negative', () {
      expect(plainEnglishEta(totalBytes: 100, doneBytes: 0, bytesPerSec: 0),
          isEmpty);
      expect(plainEnglishEta(totalBytes: 100, doneBytes: 0, bytesPerSec: -5),
          isEmpty);
    });

    test('returns empty when remainder is zero or negative', () {
      expect(
          plainEnglishEta(totalBytes: 100, doneBytes: 100, bytesPerSec: 1000),
          isEmpty);
      expect(
          plainEnglishEta(totalBytes: 100, doneBytes: 200, bytesPerSec: 1000),
          isEmpty);
    });

    test('says "Almost done" under five seconds', () {
      final out = plainEnglishEta(
        totalBytes: 1000,
        doneBytes: 980,
        bytesPerSec: 10,
      );
      expect(out, 'Almost done');
    });

    test('rounds short seconds to nearest 5', () {
      final out = plainEnglishEta(
        totalBytes: 1000,
        doneBytes: 0,
        bytesPerSec: 25, // 40s
      );
      expect(out, 'About 40 seconds left');
    });

    test('uses minutes between 90s and 1h', () {
      final out = plainEnglishEta(
        totalBytes: 60 * 1024 * 1024,
        doneBytes: 0,
        bytesPerSec: 256 * 1024, // ~240s = 4 minutes
      );
      expect(out, 'About 4 minutes left');
    });

    test('uses singular "minute" for 1 minute', () {
      final out = plainEnglishEta(
        totalBytes: 100,
        doneBytes: 0,
        bytesPerSec: 100 / 100, // 100s = 2 minutes after rounding
      );
      expect(out, 'About 2 minutes left');
    });

    test('uses hours past 1h', () {
      final out = plainEnglishEta(
        totalBytes: 5000,
        doneBytes: 0,
        bytesPerSec: 1, // 5000s ~ 1.4 hours
      );
      expect(out, contains('hour'));
    });
  });

  group('isSlowSpeed', () {
    test('flags speeds under 100 KB/s', () {
      expect(isSlowSpeed(50 * 1024), isTrue);
    });
    test('does not flag fast speeds', () {
      expect(isSlowSpeed(500 * 1024), isFalse);
    });
    test('does not flag zero', () {
      expect(isSlowSpeed(0), isFalse);
    });
  });
}
