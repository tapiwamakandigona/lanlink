import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/file_category.dart';

void main() {
  test('categorises common extensions', () {
    expect(fileCategoryFor('IMG_1234.JPG'), FileCategory.image);
    expect(fileCategoryFor('holiday.heic'), FileCategory.image);
    expect(fileCategoryFor('clip.mp4'), FileCategory.video);
    expect(fileCategoryFor('song.flac'), FileCategory.audio);
    expect(fileCategoryFor('report.pdf'), FileCategory.document);
    expect(fileCategoryFor('notes.md'), FileCategory.document);
    expect(fileCategoryFor('backup.tar'), FileCategory.archive);
    expect(fileCategoryFor('app-release.apk'), FileCategory.apk);
    expect(fileCategoryFor('bundle.aab'), FileCategory.apk);
  });

  test('unknown, missing, or trailing-dot extensions are other', () {
    expect(fileCategoryFor('binary.xyz123'), FileCategory.other);
    expect(fileCategoryFor('Makefile'), FileCategory.other);
    expect(fileCategoryFor('weird.'), FileCategory.other);
    expect(fileCategoryFor(''), FileCategory.other);
  });

  test('only the last extension counts', () {
    expect(fileCategoryFor('archive.tar.gz'), FileCategory.archive);
    expect(fileCategoryFor('photo.png.exe'), FileCategory.other);
  });
}
