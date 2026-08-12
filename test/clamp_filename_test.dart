import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/safe_paths.dart';

void main() {
  group('clampFileNameSegment', () {
    test('short names pass through untouched', () {
      expect(clampFileNameSegment('photo.jpg'), 'photo.jpg');
      expect(clampFileNameSegment('a' * 180), 'a' * 180);
    });

    test('long name is clamped under the byte budget, extension kept', () {
      final name = '${'a' * 1000}.bin';
      final out = clampFileNameSegment(name);
      expect(utf8.encode(out).length, lessThanOrEqualTo(180));
      expect(out, endsWith('.bin'));
      expect(out, contains('~'));
    });

    test('distinct long names stay distinct', () {
      final a = clampFileNameSegment('${'a' * 500}x.bin');
      final b = clampFileNameSegment('${'a' * 500}y.bin');
      expect(a, isNot(b));
    });

    test('same long name clamps deterministically', () {
      final name = '${'z' * 400}.txt';
      expect(clampFileNameSegment(name), clampFileNameSegment(name));
    });

    test('multibyte name clamps on code-unit boundary within budget', () {
      final name = '${'\u{1F600}' * 200}.png'; // 4 bytes per emoji
      final out = clampFileNameSegment(name);
      expect(utf8.encode(out).length, lessThanOrEqualTo(180));
      expect(out, endsWith('.png'));
    });

    test('long extension is not treated as an extension', () {
      final name = '${'a' * 100}.${'b' * 200}';
      final out = clampFileNameSegment(name);
      expect(utf8.encode(out).length, lessThanOrEqualTo(180));
    });

    test('splitSafeRelativePath clamps each segment', () {
      final segs = splitSafeRelativePath('folder/${'a' * 1000}.bin');
      expect(segs, hasLength(2));
      expect(segs[0], 'folder');
      expect(utf8.encode(segs[1]).length, lessThanOrEqualTo(180));
      expect(segs[1], endsWith('.bin'));
    });
  });
}
