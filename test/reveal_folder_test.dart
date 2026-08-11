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

  group('openFileCommandFor', () {
    test('desktop platforms open with the default app', () {
      expect(openFileCommandFor('windows', r'C:\Users\a\Downloads\a.pdf'),
          ['explorer', r'C:\Users\a\Downloads\a.pdf']);
      expect(openFileCommandFor('macos', '/Users/a/Downloads/a.pdf'),
          ['open', '/Users/a/Downloads/a.pdf']);
      expect(openFileCommandFor('linux', '/home/a/Downloads/a.pdf'),
          ['xdg-open', '/home/a/Downloads/a.pdf']);
    });

    test('mobile and unknown platforms return null', () {
      expect(openFileCommandFor('android', '/x/a.pdf'), isNull);
      expect(openFileCommandFor('ios', '/x/a.pdf'), isNull);
      expect(openFileCommandFor('fuchsia', '/x/a.pdf'), isNull);
    });

    test('file path is a single argument (spaces survive)', () {
      expect(openFileCommandFor('linux', '/home/a/My File.pdf'),
          ['xdg-open', '/home/a/My File.pdf']);
    });
  });
}
