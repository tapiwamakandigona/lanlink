import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/platform/android_apps.dart';
import 'package:lanlink/core/platform/media_library.dart';
import 'package:lanlink/core/util/picker_filter.dart';
import 'package:lanlink/ui/picker/share_picker_page.dart';

AndroidAppInfo _app(String label, String pkg, {int size = 1000}) =>
    AndroidAppInfo(label: label, packageName: pkg, apkPath: '/a', size: size);

FileInfo _file(String name, {int size = 100}) => FileInfo(
      id: name,
      fileName: name,
      size: size,
      fileType: fileTypeForName(name),
      localPath: '/picked/$name',
    );

MediaItem _media(
  String name, {
  String bucket = 'Camera',
  String path = '/storage/emulated/0/DCIM/Camera/x.jpg',
  bool isVideo = false,
  int size = 500,
}) =>
    MediaItem(
      id: name.hashCode,
      name: name,
      path: path,
      size: size,
      isVideo: isVideo,
      dateModified: 0,
      bucket: bucket,
    );

void main() {
  group('filterApps', () {
    final apps = [
      _app('WhatsApp', 'com.whatsapp'),
      _app('Maps', 'com.google.android.apps.maps'),
      _app('LanLink', 'com.lanlink.app'),
    ];

    test('empty query returns everything unchanged', () {
      expect(filterApps(apps, ''), apps);
      expect(filterApps(apps, '   '), apps);
    });

    test('matches label case-insensitively', () {
      expect(filterApps(apps, 'whats').single.label, 'WhatsApp');
      expect(filterApps(apps, 'LANLINK').single.label, 'LanLink');
    });

    test('matches package name too', () {
      expect(filterApps(apps, 'google').single.label, 'Maps');
    });

    test('no match yields empty list', () {
      expect(filterApps(apps, 'zzz'), isEmpty);
    });
  });

  group('filterMedia', () {
    final items = [
      _media('IMG_001.jpg'),
      _media('holiday.mp4', isVideo: true, bucket: 'Movies'),
      _media('screenshot.png', bucket: 'Screenshots'),
    ];

    test('empty query returns everything', () {
      expect(filterMedia(items, ''), items);
    });

    test('matches file name', () {
      expect(filterMedia(items, 'img').single.name, 'IMG_001.jpg');
    });

    test('matches album / bucket name', () {
      expect(filterMedia(items, 'movies').single.name, 'holiday.mp4');
    });
  });

  group('cameraRoll', () {
    test('keeps Camera bucket and DCIM paths only', () {
      final items = [
        _media('a.jpg', bucket: 'Camera', path: '/x/a.jpg'),
        _media('b.jpg', bucket: 'Other', path: '/storage/DCIM/b.jpg'),
        _media('c.png', bucket: 'Screenshots', path: '/x/Pictures/c.png'),
      ];
      final roll = cameraRoll(items);
      expect(roll.map((m) => m.name), ['a.jpg', 'b.jpg']);
    });

    test('falls back to everything when no camera bucket exists', () {
      final items = [
        _media('c.png', bucket: 'Screenshots', path: '/x/Pictures/c.png'),
      ];
      expect(cameraRoll(items), items);
    });
  });

  group('filterFiles', () {
    final files = [
      _file('backup.zip'),
      _file('Report.PDF'),
      _file('site.tar.gz'),
      _file('Makefile'),
      _file('firmware.Bin.OLD'),
    ];

    test('empty query returns everything, whatever the extensions', () {
      expect(filterFiles(files, ''), files);
      expect(filterFiles(files, '   '), files);
    });

    test('matches common archive extensions', () {
      expect(filterFiles(files, 'zip').single.fileName, 'backup.zip');
      expect(filterFiles(files, 'tar.gz').single.fileName, 'site.tar.gz');
    });

    test('is case-insensitive across arbitrary extensions', () {
      expect(filterFiles(files, 'pdf').single.fileName, 'Report.PDF');
      expect(filterFiles(files, '.bin').single.fileName, 'firmware.Bin.OLD');
    });

    test('handles extensionless files by whole-name match', () {
      expect(filterFiles(files, 'makef').single.fileName, 'Makefile');
    });

    test('no match yields an empty list', () {
      expect(filterFiles(files, 'nope'), isEmpty);
    });
  });

  group('selection totals', () {
    test('mediaTotalSize and appsTotalSize sum byte sizes', () {
      expect(mediaTotalSize([_media('a', size: 5), _media('b', size: 7)]), 12);
      expect(
          appsTotalSize([_app('a', 'a', size: 3), _app('b', 'b', size: 4)]), 7);
      expect(mediaTotalSize(const []), 0);
    });

    test('filesTotalSize sums arbitrary picked files', () {
      expect(
          filesTotalSize([_file('a.zip', size: 8), _file('b', size: 9)]), 17);
      expect(filesTotalSize(const []), 0);
    });
  });

  group('safeApkName', () {
    test('replaces illegal filesystem characters', () {
      expect(safeApkName('What/sApp: Pro?'), 'What_sApp_ Pro_');
    });

    test('collapses runs of illegal characters into one underscore', () {
      expect(safeApkName('///'), '_');
    });

    test('falls back to "app" for an empty label', () {
      expect(safeApkName('   '), 'app');
    });
  });
}
