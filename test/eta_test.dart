import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
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

  group('TransferSession rolling speed', () {
    TransferSession session(int totalBytes) => TransferSession(
          sessionId: 's',
          direction: TransferDirection.send,
          peer: Device(
            alias: 'peer',
            version: '2.1',
            deviceModel: 'test',
            deviceType: 'headless',
            fingerprint: 'fp',
            port: 53317,
            protocol: 'http',
            ip: '127.0.0.1',
          ),
          files: {
            'f': FileProgress(
              file: FileInfo(
                id: 'f',
                fileName: 'big.bin',
                size: totalBytes,
                fileType: 'other',
              ),
              status: TransferStatus.transferring,
            ),
          },
          status: TransferStatus.transferring,
        );

    test('tracks the trailing window, not the lifetime average', () {
      final s = session(1000 * 1000 * 1000);
      final t0 = s.startedAt;
      // 10 seconds at 10 MB/s...
      for (var i = 1; i <= 10; i++) {
        s.files['f']!.bytes = 10 * 1000 * 1000 * i;
        s.recomputeSpeedAt(t0.add(Duration(seconds: i)));
      }
      expect(s.speedBytesPerSec, closeTo(10 * 1000 * 1000, 2 * 1000 * 1000));
      // ...then the link collapses to 1 MB/s for 10 more seconds.
      for (var i = 1; i <= 10; i++) {
        s.files['f']!.bytes = 100 * 1000 * 1000 + 1000 * 1000 * i;
        s.recomputeSpeedAt(t0.add(Duration(seconds: 10 + i)));
      }
      // Lifetime average would report ~5.5 MB/s; the window must be ~1 MB/s.
      expect(s.speedBytesPerSec, closeTo(1000 * 1000, 300 * 1000),
          reason: 'speed (and the ETA derived from it) must reflect the '
              'current link, not history');
    });

    test('falls back to lifetime average right at the start', () {
      final s = session(1000 * 1000);
      s.files['f']!.bytes = 500 * 1000;
      s.recomputeSpeedAt(s.startedAt.add(const Duration(milliseconds: 100)));
      expect(s.speedBytesPerSec, greaterThan(0));
    });
  });
}
