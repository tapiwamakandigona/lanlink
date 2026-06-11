import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/platform/android_apps.dart';
import 'package:lanlink/core/platform/media_library.dart';
import 'package:lanlink/ui/picker/share_picker_page.dart';

AndroidAppInfo _app(String label, String pkg, int size, {Uint8List? icon}) =>
    AndroidAppInfo(
      label: label,
      packageName: pkg,
      apkPath: '/apk/$pkg',
      size: size,
      icon: icon,
    );

MediaItem _media(int id, String name, {bool isVideo = false, int size = 100}) =>
    MediaItem(
      id: id,
      name: name,
      path: '/dcim/$name',
      size: size,
      isVideo: isVideo,
      dateModified: id,
      bucket: 'Camera',
    );

/// Holds the picker's pop result so tests can assert on it after the fact.
class _Result {
  List<FileInfo>? value;
}

Future<_Result> _pump(
  WidgetTester tester, {
  required List<MediaItem> media,
  required List<AndroidAppInfo> apps,
  SharePickerTab tab = SharePickerTab.photos,
}) async {
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result.value = await Navigator.of(context).push<List<FileInfo>>(
                MaterialPageRoute(
                  builder: (_) => SharePickerPage(
                    initialTab: tab,
                    loadMedia: () async => media,
                    loadApps: () async => apps,
                    thumbnailLoader: (_) async => null,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  final media = [
    _media(1, 'IMG_001.jpg', size: 1000),
    _media(2, 'IMG_002.jpg', size: 2000),
    _media(3, 'clip.mp4', isVideo: true, size: 4000),
  ];
  final apps = [
    _app('WhatsApp', 'com.whatsapp', 50 * 1024 * 1024),
    _app('Calculator', 'com.calc', 5 * 1024 * 1024),
  ];

  testWidgets('photos tab shows grid, select-all stages everything',
      (tester) async {
    final result = await _pump(tester, media: media, apps: apps);

    expect(find.byKey(const Key('media-1')), findsOneWidget);
    expect(find.text('3 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('picker-select-all')));
    await tester.pump();
    expect(find.textContaining('3 items • '), findsOneWidget);

    await tester.tap(find.byKey(const Key('picker-add')));
    await tester.pumpAndSettle();

    expect(result.value, isNotNull);
    expect(result.value, hasLength(3));
  });

  testWidgets('returns FileInfos with correct names, sizes and types',
      (tester) async {
    final result = await _pump(tester, media: media, apps: apps);

    await tester.tap(find.byKey(const Key('media-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('media-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('picker-add')));
    await tester.pumpAndSettle();

    final files = result.value!;
    expect(files, hasLength(2));
    expect(
      files.map((f) => f.fileName),
      containsAll(['IMG_001.jpg', 'clip.mp4']),
    );
    final clip = files.firstWhere((f) => f.fileName == 'clip.mp4');
    expect(clip.size, 4000);
    expect(clip.fileType, 'video');
    expect(clip.localPath, '/dcim/clip.mp4');
  });

  testWidgets('selected apps come back as .apk FileInfos', (tester) async {
    final result =
        await _pump(tester, media: media, apps: apps, tab: SharePickerTab.apps);

    await tester.tap(find.byKey(const Key('app-com.whatsapp')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('picker-add')));
    await tester.pumpAndSettle();

    final files = result.value!;
    expect(files, hasLength(1));
    expect(files.single.fileName, 'WhatsApp.apk');
    expect(files.single.fileType, 'app');
    expect(files.single.localPath, '/apk/com.whatsapp');
  });

  testWidgets('search filters the apps tab and selection survives it',
      (tester) async {
    await _pump(tester, media: media, apps: apps, tab: SharePickerTab.apps);

    expect(find.byKey(const Key('app-com.whatsapp')), findsOneWidget);
    expect(find.byKey(const Key('app-com.calc')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-com.whatsapp')));
    await tester.pump();
    expect(find.textContaining('1 item • '), findsOneWidget);

    await tester.enterText(find.byKey(const Key('picker-search')), 'calc');
    await tester.pump();
    expect(find.byKey(const Key('app-com.whatsapp')), findsNothing);
    expect(find.byKey(const Key('app-com.calc')), findsOneWidget);

    // Hidden by the filter, but still selected.
    expect(find.textContaining('1 item • '), findsOneWidget);
  });

  testWidgets('add button disabled with empty selection', (tester) async {
    await _pump(tester, media: media, apps: apps);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('picker-add')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Nothing selected yet'), findsOneWidget);
  });

  testWidgets('video tiles show a play badge', (tester) async {
    await _pump(tester, media: media, apps: apps);
    final badge = find.descendant(
      of: find.byKey(const Key('media-3')),
      matching: find.byIcon(Icons.play_circle_fill),
    );
    expect(badge, findsOneWidget);
  });

  testWidgets('app icons render when provided', (tester) async {
    // 1x1 transparent PNG.
    final png = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
    final iconApp = _app('Iconic', 'com.iconic', 10, icon: png);
    await _pump(tester,
        media: media, apps: [iconApp], tab: SharePickerTab.apps);
    final image = find.descendant(
      of: find.byKey(const Key('app-com.iconic')),
      matching: find.byType(Image),
    );
    expect(image, findsOneWidget);
  });
}
