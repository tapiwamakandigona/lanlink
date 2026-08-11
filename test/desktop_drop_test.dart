import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/dropped_paths.dart';
import 'package:lanlink/ui/widgets/desktop_drop_region.dart';

void main() {
  group('fileInfosForDroppedPaths', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lanlink_drop_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('plain files become one FileInfo each with size and type', () async {
      final a = File('${tmp.path}/photo.jpg')..writeAsBytesSync([1, 2, 3]);
      final b = File('${tmp.path}/notes.txt')..writeAsBytesSync([4, 5]);

      final infos = await fileInfosForDroppedPaths([a.path, b.path]);

      expect(infos, hasLength(2));
      final photo = infos.firstWhere((f) => f.fileName == 'photo.jpg');
      expect(photo.size, 3);
      expect(photo.fileType, 'image');
      expect(photo.localPath, a.path);
      final notes = infos.firstWhere((f) => f.fileName == 'notes.txt');
      expect(notes.size, 2);
    });

    test('a dropped folder is walked recursively with structure preserved',
        () async {
      final dir = Directory('${tmp.path}/Holiday/clips')
        ..createSync(recursive: true);
      File('${tmp.path}/Holiday/IMG_001.jpg').writeAsBytesSync([1]);
      File('${dir.path}/video.mp4').writeAsBytesSync([2, 3]);

      final infos = await fileInfosForDroppedPaths(['${tmp.path}/Holiday']);

      expect(infos.map((f) => f.fileName).toList()..sort(), [
        'Holiday/IMG_001.jpg',
        'Holiday/clips/video.mp4',
      ]);
    });

    test('missing paths are skipped, never thrown', () async {
      final real = File('${tmp.path}/real.bin')..writeAsBytesSync([9]);
      final infos = await fileInfosForDroppedPaths(
          ['${tmp.path}/does-not-exist', real.path]);
      expect(infos, hasLength(1));
      expect(infos.single.fileName, 'real.bin');
    });
  });

  group('DesktopDropRegion', () {
    testWidgets('wraps the child in a DropTarget on desktop platforms',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DesktopDropRegion(
          onFiles: (_) {},
          child: const Text('body'),
        ),
      ));
      expect(find.text('body'), findsOneWidget);
      // The test host is a desktop OS, so the drop affordance must be there.
      expect(DesktopDropRegion.isSupported, isTrue);
      expect(find.byType(DropTarget), findsOneWidget);
    });
  });
}
