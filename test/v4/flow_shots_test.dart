// Renders the real end-to-end flow (home with live sessions, send radar,
// receive QR, history) to PNGs so the UI flow can be reviewed as pixels
// rather than as code. Companion to app_screens_screenshots_test.dart.
//
//   FLOW_SHOTS_DIR=/some/dir flutter test test/v4/flow_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/models/device.dart';

import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/platform/android_apps.dart';
import 'package:lanlink/core/platform/media_library.dart';
import 'package:lanlink/core/platform/media_permissions.dart';
import 'package:lanlink/ui/picker/share_picker_page.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/history_page.dart';
import 'package:lanlink/ui/shell/home_page.dart';
import 'package:lanlink/ui/shell/receive_page.dart';
import 'package:lanlink/ui/shell/send_page.dart';
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
    Platform.environment['FLOW_SHOTS_DIR'] ?? 'build/flow_shots';

Device _peer({
  required String alias,
  required String fp,
  String type = 'mobile',
  String ip = '192.168.1.20',
}) =>
    Device(
      alias: alias,
      version: '2.1',
      deviceModel: 'Pixel 7',
      deviceType: type,
      fingerprint: fp,
      port: 53317,
      protocol: 'https',
      ip: ip,
    );

FileInfo _file(String name, int size) => FileInfo(
      id: 'id-$name',
      fileName: name,
      size: size,
      fileType: fileTypeForName(name),
      localPath: '/tmp/$name',
    );

TransferSession _session({
  required String id,
  required Device peer,
  required TransferStatus status,
  required List<FileInfo> files,
  TransferDirection direction = TransferDirection.send,
  double progress = 0,
  double speed = 0,
}) {
  final s = TransferSession(
    sessionId: id,
    direction: direction,
    peer: peer,
    files: {
      for (final f in files)
        f.id: FileProgress(
          file: f,
          status: status,
          bytes: (f.size * progress).round(),
        )
    },
    status: status,
  );
  s.speedBytesPerSec = speed;
  return s;
}

Future<AppState> _makeState(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'lanlink_alias': 'Marmalade-Fox',
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
  double height = 844,
}) async {
  const boundaryKey = Key('shot-boundary');
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
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

  testWidgets('home — live transfers + linked peer', (tester) async {
    final state = await _makeState(tester);
    final phone = _peer(alias: 'Quiet-Badger', fp: 'fp-1');
    final laptop = _peer(
        alias: 'Copper-Finch', fp: 'fp-2', type: 'desktop', ip: '192.168.1.31');
    state.seedForScreenshots(
      peers: [phone, laptop],
      linkedPeers: [phone],
      sessions: [
        _session(
          id: 's1',
          peer: phone,
          status: TransferStatus.transferring,
          files: [_file('holiday-video.mp4', 1288490188)],
          progress: 0.38,
          speed: 41 * 1024 * 1024,
        ),
        _session(
          id: 's2',
          peer: laptop,
          status: TransferStatus.completed,
          direction: TransferDirection.receive,
          files: [_file('IMG_2041.jpg', 4 * 1024 * 1024)],
          progress: 1,
        ),
      ],
    );
    await _capture(tester,
        page: const HomePage(),
        state: state,
        brightness: Brightness.light,
        name: 'home_live_light');
  });

  testWidgets('send — radar with peers', (tester) async {
    final state = await _makeState(tester);
    state.seedForScreenshots(peers: [
      _peer(alias: 'Quiet-Badger', fp: 'fp-1'),
      _peer(alias: 'Copper-Finch', fp: 'fp-2', type: 'desktop'),
      _peer(alias: 'Purple-Otter', fp: 'fp-3'),
    ]);
    await _capture(tester,
        page: const SendPage(),
        state: state,
        brightness: Brightness.light,
        name: 'send_radar_light');
  });

  testWidgets('send — empty radar', (tester) async {
    final state = await _makeState(tester);
    await _capture(tester,
        page: const SendPage(),
        state: state,
        brightness: Brightness.light,
        name: 'send_empty_light');
  });

  testWidgets('receive — QR ready', (tester) async {
    final state = await _makeState(tester);
    await _capture(tester,
        page: const ReceivePage(
          debugPayload: ConnectPayload(
            ip: '192.168.1.10',
            port: 53317,
            alias: 'Marmalade-Fox',
            fingerprint: 'self-fp',
            token: 'tok-123',
          ),
        ),
        state: state,
        brightness: Brightness.light,
        name: 'receive_qr_light');
  });

  testWidgets('receive — QR ready (dark)', (tester) async {
    final state = await _makeState(tester);
    await _capture(tester,
        page: const ReceivePage(
          debugPayload: ConnectPayload(
            ip: '192.168.1.10',
            port: 53317,
            alias: 'Marmalade-Fox',
            fingerprint: 'self-fp',
            token: 'tok-123',
          ),
        ),
        state: state,
        brightness: Brightness.dark,
        name: 'receive_qr_dark');
  });

  testWidgets('history — recent transfers', (tester) async {
    final state = await _makeState(tester);
    final phone = _peer(alias: 'Quiet-Badger', fp: 'fp-1');
    state.seedForScreenshots(
      peers: [phone],
      sessions: [
        _session(
          id: 'h1',
          peer: phone,
          status: TransferStatus.completed,
          files: [_file('holiday-video.mp4', 1288490188)],
          progress: 1,
        ),
        _session(
          id: 'h2',
          peer: phone,
          status: TransferStatus.failed,
          direction: TransferDirection.receive,
          files: [_file('project-archive.zip', 620 * 1024 * 1024)],
          progress: 0.2,
        ),
      ],
    );
    await _capture(tester,
        page: const HistoryPage(),
        state: state,
        brightness: Brightness.light,
        name: 'history_light');
  });

  testWidgets('picker — photos tab', (tester) async {
    final state = await _makeState(tester);
    final media = [
      for (var i = 0; i < 12; i++)
        MediaItem(
          id: i,
          name: 'IMG_20${40 + i}.jpg',
          path: '/dcim/IMG_20${40 + i}.jpg',
          size: (2 + i) * 1024 * 1024,
          isVideo: i % 5 == 4,
          dateModified: 1000 - i,
          bucket: 'Camera',
        ),
    ];
    await _capture(tester,
        page: SharePickerPage(
          loadMedia: () async => media,
          loadApps: () async => <AndroidAppInfo>[],
          thumbnailLoader: (_) async => null,
          requestMediaAccess: () async => MediaAccess.granted,
          openSettings: () async => true,
          pickAnyFiles: () async => const <FileInfo>[],
          mediaPathExists: (_) => true,
        ),
        state: state,
        brightness: Brightness.light,
        name: 'picker_photos_light');
  });

  testWidgets('home — desktop width', (tester) async {
    final state = await _makeState(tester);
    final phone = _peer(alias: 'Quiet-Badger', fp: 'fp-1');
    state.seedForScreenshots(
      peers: [phone],
      sessions: [
        _session(
          id: 'd1',
          peer: phone,
          status: TransferStatus.transferring,
          files: [_file('holiday-video.mp4', 1288490188)],
          progress: 0.62,
          speed: 34 * 1024 * 1024,
        ),
      ],
    );
    await _capture(tester,
        page: const HomePage(),
        state: state,
        brightness: Brightness.light,
        name: 'home_desktop_light',
        width: 560,
        height: 780);
  });
}
