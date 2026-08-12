// tryFromJson is the total, non-throwing parser for peer-controlled
// prepare-upload file entries. Everything here is something a hostile or
// buggy peer can put on the wire.
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/file_info.dart';

void main() {
  group('FileInfo.tryFromJson rejects malformed entries without throwing', () {
    test('valid entry parses', () {
      final fi = FileInfo.tryFromJson({
        'id': 'a',
        'fileName': 'photo.jpg',
        'size': 10,
        'fileType': 'image'
      });
      expect(fi, isNotNull);
      expect(fi!.size, 10);
      expect(fi.fileType, 'image');
    });
    test('numeric-string size is parsed', () {
      final fi =
          FileInfo.tryFromJson({'id': 'a', 'fileName': 'x', 'size': '4096'});
      expect(fi?.size, 4096);
    });
    test('double size is truncated', () {
      final fi =
          FileInfo.tryFromJson({'id': 'a', 'fileName': 'x', 'size': 12.9});
      expect(fi?.size, 12);
    });
    test('non-numeric size -> null', () {
      expect(FileInfo.tryFromJson({'id': 'a', 'fileName': 'x', 'size': 'big'}),
          isNull);
    });
    test('negative size -> null', () {
      expect(FileInfo.tryFromJson({'id': 'a', 'fileName': 'x', 'size': -1}),
          isNull);
    });
    test('missing id / fileName -> null', () {
      expect(FileInfo.tryFromJson({'fileName': 'x', 'size': 1}), isNull);
      expect(FileInfo.tryFromJson({'id': 'a', 'size': 1}), isNull);
      expect(
          FileInfo.tryFromJson({'id': '', 'fileName': 'x', 'size': 1}), isNull);
    });
    test('non-map input -> null, no throw', () {
      expect(FileInfo.tryFromJson('nope'), isNull);
      expect(FileInfo.tryFromJson(42), isNull);
      expect(FileInfo.tryFromJson(null), isNull);
      expect(FileInfo.tryFromJson(['a']), isNull);
    });
    test('wrong-typed optional fields degrade, no throw', () {
      final fi = FileInfo.tryFromJson({
        'id': 'a',
        'fileName': 'x',
        'size': 1,
        'fileType': 99,
        'sha256': false,
        'preview': [1],
      });
      expect(fi, isNotNull);
      expect(fi!.fileType, 'other');
      expect(fi.sha256, isNull);
      expect(fi.preview, isNull);
    });
  });
}
