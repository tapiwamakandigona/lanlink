import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/util/friendly_files.dart';

FileInfo _file(String name) => FileInfo(
      id: name,
      fileName: name,
      size: 100,
      fileType: fileTypeForName(name),
    );

void main() {
  group('describeFilesFriendly', () {
    test('empty list', () {
      expect(describeFilesFriendly(const []), 'nothing');
    });

    test('single photo', () {
      expect(describeFilesFriendly([_file('a.jpg')]), '1 photo');
    });

    test('multiple photos', () {
      expect(
        describeFilesFriendly([_file('a.jpg'), _file('b.png')]),
        '2 photos',
      );
    });

    test('photos and a video', () {
      expect(
        describeFilesFriendly([_file('a.jpg'), _file('b.png'), _file('c.mp4')]),
        '2 photos and 1 video',
      );
    });

    test('only non-media files', () {
      expect(
        describeFilesFriendly([_file('a.pdf'), _file('b.zip')]),
        '2 files',
      );
    });

    test('mixed media and files', () {
      expect(
        describeFilesFriendly([_file('a.jpg'), _file('c.mp4'), _file('b.zip')]),
        '1 photo, 1 video and 1 file',
      );
    });
  });
}
