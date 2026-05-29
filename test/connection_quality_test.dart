import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/connection_quality.dart';

void main() {
  group('qualityForPeerCount', () {
    test('zero peers = none', () {
      expect(qualityForPeerCount(0), ConnectionQuality.none);
    });
    test('one or two peers = fair', () {
      expect(qualityForPeerCount(1), ConnectionQuality.fair);
      expect(qualityForPeerCount(2), ConnectionQuality.fair);
    });
    test('three or more peers = strong', () {
      expect(qualityForPeerCount(3), ConnectionQuality.strong);
      expect(qualityForPeerCount(10), ConnectionQuality.strong);
    });
  });

  group('ConnectionQualityLabel', () {
    test('labels are human friendly', () {
      expect(ConnectionQuality.none.label, 'No devices yet');
      expect(ConnectionQuality.weak.label, 'Weak connection');
      expect(ConnectionQuality.fair.label, 'Connected');
      expect(ConnectionQuality.strong.label, 'Strong connection');
    });

    test('bars range from 0 to 3', () {
      expect(ConnectionQuality.none.bars, 0);
      expect(ConnectionQuality.weak.bars, 1);
      expect(ConnectionQuality.fair.bars, 2);
      expect(ConnectionQuality.strong.bars, 3);
    });
  });
}
