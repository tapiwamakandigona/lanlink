// Renders real app screens (first-run, home, settings, help) to PNG files
// for design review — the critic-pass companion to gallery_screenshots_test.
//
// Output dir comes from APP_SHOTS_DIR (falls back to build/app_shots):
//   APP_SHOTS_DIR=/some/dir flutter test test/v4/app_screens_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/help_page.dart';
import 'package:lanlink/ui/settings_page.dart';
import 'package:lanlink/ui/shell/first_run_page.dart';
import 'package:lanlink/ui/shell/home_page.dart';
import 'package:lanlink/ui/v4/v4.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

final String _outDir =
    Platform.environment['APP_SHOTS_DIR'] ?? 'build/app_shots';

Future<AppState> _makeState(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'lanlink_alias': 'Kitchen laptop',
    'lanlink_last_onboarded_version': 'v4',
    'lanlink_connectivity_default_applied_v1': true,
  });
  late AppState state;
  await tester.runAsync(() async {
    state = AppState.forScreenshots(settings: await AppSettings.load());
  });
  return state;
}

Future<void> _capture(
  WidgetTester tester, {
  required Widget page,
  required AppState state,
  required Brightness brightness,
  required String name,
  double width = 390,
}) async {
  const boundaryKey = Key('shot-boundary');
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(RepaintBoundary(
    key: boundaryKey,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: state.settings),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.light
            ? EmberTheme.light()
            : EmberTheme.dark(),
        home: page,
      ),
    ),
  ));
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

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('capture first-run — $suffix', (tester) async {
      final state = await _makeState(tester);
      await _capture(tester,
          page: FirstRunPage(onDone: () {}),
          state: state,
          brightness: brightness,
          name: 'first_run_$suffix');
    });

    testWidgets('capture home — $suffix', (tester) async {
      final state = await _makeState(tester);
      await _capture(tester,
          page: const HomePage(),
          state: state,
          brightness: brightness,
          name: 'home_$suffix');
    });

    testWidgets('capture settings — $suffix', (tester) async {
      final state = await _makeState(tester);
      await _capture(tester,
          page: const SettingsPage(),
          state: state,
          brightness: brightness,
          name: 'settings_$suffix');
    });

    testWidgets('capture help — $suffix', (tester) async {
      final state = await _makeState(tester);
      await _capture(tester,
          page: const HelpPage(),
          state: state,
          brightness: brightness,
          name: 'help_$suffix');
    });
  }
}
