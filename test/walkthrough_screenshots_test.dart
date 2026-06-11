// Golden walkthrough of the advanced-mode journey on phone and desktop
// frames: home with devices, the add-files sheet, the direct-link QR
// screen, live progress, and the finished state. These double as visual
// regression tests in CI.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/platform/android_apps.dart';
import 'package:lanlink/core/platform/local_hotspot.dart';
import 'package:lanlink/core/platform/media_library.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/theme/app_theme.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/history_page.dart';
import 'package:lanlink/ui/home_page.dart';
import 'package:lanlink/ui/hotspot/direct_link_page.dart';
import 'package:lanlink/ui/picker/share_picker_page.dart';
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
    'Roboto-Bold.ttf'
  ]) {
    roboto.addFont(
      File('$_fontDir/$f').readAsBytes().then((b) => b.buffer.asByteData()),
    );
  }
  await roboto.load();
  // The direct-link page styles credentials with fontFamily 'monospace';
  // map that family to Roboto in tests so it doesn't render as tofu.
  final mono = FontLoader('monospace')
    ..addFont(File('$_fontDir/Roboto-Regular.ttf')
        .readAsBytes()
        .then((b) => b.buffer.asByteData()));
  await mono.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(File('$_fontDir/MaterialIcons-Regular.otf')
        .readAsBytes()
        .then((b) => b.buffer.asByteData()));
  await icons.load();
}

Device _peer(String alias, {String type = 'mobile', String model = 'Pixel 7'}) {
  return Device(
    alias: alias,
    version: '2.1',
    deviceModel: model,
    deviceType: type,
    fingerprint: 'fp-$alias',
    port: 53317,
    protocol: 'http',
    ip: '192.168.1.23',
  );
}

FileInfo _file(String name, int size) => FileInfo(
      id: name,
      fileName: name,
      size: size,
      fileType: fileTypeForName(name.split('/').last),
    );

Widget _app(AppState state, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: state.settings),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: child,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'lanlink_alias': "Kylie's phone",
      'lanlink_simple_mode_v1': false,
      'lanlink_connectivity_default_applied_v1': true,
    });
  });

  Future<void> shoot(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<AppState> stateWithPeers(WidgetTester tester,
      {List<TransferSession> sessions = const []}) async {
    late AppState state;
    await tester.runAsync(() async {
      await _loadFonts();
      state = AppState.forScreenshots(settings: await AppSettings.load());
    });
    state.seedForScreenshots(
      peers: [
        _peer("Rudo's phone"),
        _peer('Office laptop', type: 'desktop', model: 'Windows 11'),
      ],
      sessions: sessions,
    );
    return state;
  }

  TransferSession makeSession(TransferStatus status, double fraction) {
    final files = [
      _file('Holiday/IMG_2041.jpg', 3400000),
      _file('Holiday/IMG_2042.jpg', 2900000),
      _file('Holiday/clips/beach.mp4', 48000000),
    ];
    return TransferSession(
      sessionId: 'walk-$status',
      direction: TransferDirection.send,
      peer: _peer("Rudo's phone"),
      files: {
        for (final f in files)
          f.id: FileProgress(
            file: f,
            bytes: (f.size * fraction).round(),
            status: status == TransferStatus.completed
                ? TransferStatus.completed
                : TransferStatus.transferring,
          ),
      },
      status: status,
    );
  }

  testWidgets('phone: home with devices', (tester) async {
    phone(tester);
    final state = await stateWithPeers(tester);
    await tester.pumpWidget(_app(state, const HomePage()));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'walk_phone_home');
  });

  testWidgets('phone: add-files sheet with folder option', (tester) async {
    phone(tester);
    // Render the sheet the way a real Android phone shows it (photos,
    // apps and Move-my-photos entries included).
    MediaLibrary.debugForceSupported = true;
    AndroidApps.debugForceSupported = true;
    addTearDown(() {
      MediaLibrary.debugForceSupported = false;
      AndroidApps.debugForceSupported = false;
    });
    final state = await stateWithPeers(tester);
    await tester.pumpWidget(_app(state, const HomePage()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Send files'));
    await tester.pumpAndSettle();
    await shoot(tester, 'walk_phone_add_sheet');
  });

  testWidgets('phone: direct link QR', (tester) async {
    phone(tester);
    final state = await stateWithPeers(tester);
    await tester.pumpWidget(_app(
      state,
      const DirectLinkPage(
        debugInfo: HotspotInfo(
          ssid: 'AndroidShare_7281',
          password: 'q3vXk9mTpZ2w',
          hostIps: ['192.168.43.1'],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'walk_phone_direct_link');
  });

  testWidgets('phone: sending in progress', (tester) async {
    phone(tester);
    final state = await stateWithPeers(
      tester,
      sessions: [makeSession(TransferStatus.transferring, 0.62)],
    );
    await tester.pumpWidget(_app(state, const HomePage()));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'walk_phone_sending');
  });

  testWidgets('phone: transfer finished (history)', (tester) async {
    phone(tester);
    final state = await stateWithPeers(
      tester,
      sessions: [makeSession(TransferStatus.completed, 1.0)],
    );
    await tester.pumpWidget(_app(state, const HistoryPage()));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'walk_phone_done');
  });

  testWidgets('phone: share picker with photo grid', (tester) async {
    phone(tester);
    await tester.runAsync(_loadFonts);

    Future<Uint8List> swatch(Color color) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 64, 64),
        Paint()..color = color,
      );
      final image = await recorder.endRecording().toImage(64, 64);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    }

    late List<Uint8List> swatches;
    await tester.runAsync(() async {
      swatches = await Future.wait([
        swatch(const Color(0xFF7FB3FF)),
        swatch(const Color(0xFFFFC857)),
        swatch(const Color(0xFF8BC34A)),
        swatch(const Color(0xFFB39DDB)),
        swatch(const Color(0xFF80CBC4)),
        swatch(const Color(0xFFEF9A9A)),
      ]);
    });

    final items = [
      for (var i = 0; i < 6; i++)
        MediaItem(
          id: i,
          name: i == 2 ? 'beach_day.mp4' : 'IMG_20${40 + i}.jpg',
          path: '/dcim/$i',
          size: 2400000 + i * 700000,
          isVideo: i == 2,
          dateModified: 100 - i,
          bucket: 'Camera',
        ),
    ];

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SharePickerPage(
        loadMedia: () async => items,
        loadApps: () async => const [
          AndroidAppInfo(
            label: 'LanLink',
            packageName: 'com.lanlink.app',
            apkPath: '/apk',
            size: 24000000,
          ),
        ],
        thumbnailLoader: (item) async => swatches[item.id],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    // Image.memory decodes asynchronously; precache the swatches inside
    // runAsync so the thumbnails actually paint in the golden.
    final pickerContext = tester.element(find.byType(SharePickerPage));
    await tester.runAsync(() async {
      for (final bytes in swatches) {
        await precacheImage(MemoryImage(bytes), pickerContext);
      }
    });
    await tester.pump(const Duration(milliseconds: 100));
    // Select a couple of items so the running total shows.
    await tester.tap(find.byKey(const Key('media-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('media-2')));
    await tester.pump(const Duration(milliseconds: 200));
    await shoot(tester, 'walk_phone_picker');
  });

  testWidgets('desktop: home with devices', (tester) async {
    desktop(tester);
    final state = await stateWithPeers(tester);
    await tester.pumpWidget(_app(state, const HomePage()));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'walk_desktop_home');
  });

  testWidgets('desktop: sending in progress', (tester) async {
    desktop(tester);
    final state = await stateWithPeers(
      tester,
      sessions: [makeSession(TransferStatus.transferring, 0.41)],
    );
    await tester.pumpWidget(_app(state, const HomePage()));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'walk_desktop_sending');
  });
}
