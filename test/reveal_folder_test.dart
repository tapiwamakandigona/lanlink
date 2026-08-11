import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/reveal_folder.dart';

void main() {
  group('revealCommandFor', () {
    test('desktop platforms map to their file manager', () {
      expect(revealCommandFor('windows', r'C:\Users\a\Downloads'),
          ['explorer', r'C:\Users\a\Downloads']);
      expect(revealCommandFor('macos', '/Users/a/Downloads'),
          ['open', '/Users/a/Downloads']);
      expect(revealCommandFor('linux', '/home/a/Downloads'),
          ['xdg-open', '/home/a/Downloads']);
    });

    test('mobile and unknown platforms return null', () {
      expect(revealCommandFor('android', '/x'), isNull);
      expect(revealCommandFor('ios', '/x'), isNull);
      expect(revealCommandFor('fuchsia', '/x'), isNull);
    });

    test('folder is passed as a single argument (no shell splitting)', () {
      final cmd = revealCommandFor('linux', '/home/a/My Files');
      expect(cmd, ['xdg-open', '/home/a/My Files']);
    });
  });
}
