// Renders the v4 gallery to PNG files for design review.
//
// Output dir comes from V4_SHOTS_DIR (falls back to build/v4_shots):
//   V4_SHOTS_DIR=/some/dir flutter test test/v4/gallery_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/ui/v4/gallery.dart';

/// Real Material fonts from the Flutter SDK cache so the shots show actual
/// type, not the Ahem test font.
final String _fontDir = () {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    fail('FLUTTER_ROOT is not set; run via `flutter test`.');
  }
  return '$root/bin/cache/artifacts/material_fonts';
}();

Future<void> _loadFonts() async {
  final roboto = FontLoader('Roboto');
  for (final f in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    roboto.addFont(
      File('$_fontDir/$f').readAsBytes().then((b) => b.buffer.asByteData()),
    );
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(File('$_fontDir/MaterialIcons-Regular.otf')
        .readAsBytes()
        .then((b) => b.buffer.asByteData()));
  await icons.load();
}

final String _outDir = Platform.environment['V4_SHOTS_DIR'] ?? 'build/v4_shots';

Future<void> _capture(
  WidgetTester tester, {
  required double width,
  required ThemeMode mode,
  required String name,
}) async {
  const boundaryKey = Key('shot-boundary');
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(RepaintBoundary(
    key: boundaryKey,
    child: V4GalleryApp(themeMode: mode),
  ));
  await tester.pump(const Duration(milliseconds: 400));

  // Grow the surface to the gallery's full content height so the whole
  // page is on one PNG.
  final position =
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  final total = (1000 + position.maxScrollExtent).ceilToDouble();
  tester.view.physicalSize = Size(width, total);
  await tester.pump(const Duration(milliseconds: 400));

  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('capture gallery — phone light', (tester) async {
    await _capture(tester,
        width: 390, mode: ThemeMode.light, name: 'gallery_phone_light');
  });

  testWidgets('capture gallery — phone dark', (tester) async {
    await _capture(tester,
        width: 390, mode: ThemeMode.dark, name: 'gallery_phone_dark');
  });

  testWidgets('capture gallery — desktop light', (tester) async {
    await _capture(tester,
        width: 1200, mode: ThemeMode.light, name: 'gallery_desktop_light');
  });

  testWidgets('capture gallery — desktop dark', (tester) async {
    await _capture(tester,
        width: 1200, mode: ThemeMode.dark, name: 'gallery_desktop_dark');
  });
}
