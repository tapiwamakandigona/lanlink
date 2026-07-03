// Renders the v4 app shell to PNG files for design review.
//
// Output dir comes from V4_SHOTS_DIR (falls back to build/v4_shots):
//   V4_SHOTS_DIR=/some/dir flutter test test/shell/shell_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/state/app_state.dart';
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
    Platform.environment['V4_SHOTS_DIR'] ?? 'build/v4_shots';

Device _peer(String alias, String fp, {bool verified = false}) => Device(
      alias: alias,
      version: '2.1',
      deviceModel: alias,
      deviceType: alias.contains('Book') ? 'desktop' : 'mobile',
      fingerprint: fp,
      port: 53317,
      protocol: 'http',
      ip: '192.168.1.20',
      verified: verified,
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
  required TransferStatus status,
  String? groupId,
  required List<FileInfo> files,
  double progress = 0,
}) {
  final s = TransferSession(
    sessionId: id,
    direction: TransferDirection.send,
    peer: _peer('Pixel 7', 'peer-fp'),
    files: {
      for (final f in files)
        f.id: FileProgress(
          file: f,
          status: status,
          bytes: (f.size * progress).round(),
        ),
    },
    status: status,
  );
  s.groupId = groupId;
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
  required AppState state,
  required Widget page,
  required ThemeMode mode,
  required String name,
  Future<void> Function(WidgetTester)? afterPump,
}) async {
  const boundaryKey = Key('shot-boundary');
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
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
        themeMode: mode,
        theme: EmberTheme.light(),
        darkTheme: EmberTheme.dark(),
        home: page,
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  if (afterPump != null) await afterPump(tester);

  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  // Dispose the page so periodic timers (send radar rescan) are cancelled.
  await tester.pumpWidget(const SizedBox());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  const modes = [(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')];

  for (final (mode, suffix) in modes) {
    testWidgets('home empty ($suffix)', (tester) async {
      final state = await _makeState(tester);
      await _capture(tester,
          state: state,
          page: const HomePage(),
          mode: mode,
          name: 'home_empty_$suffix');
    });

    testWidgets('home with sessions ($suffix)', (tester) async {
      final state = await _makeState(tester);
      state.seedForScreenshots(sessions: [
        _session(
          id: 'a',
          status: TransferStatus.transferring,
          groupId: 'g1',
          files: [for (var i = 0; i < 14; i++) _file('IMG_$i.jpg', 3200000)],
          progress: 0.62,
        ),
        _session(
          id: 'b',
          status: TransferStatus.awaitingAccept,
          groupId: 'g1',
          files: [_file('holiday.mp4', 812000000)],
        ),
        _session(
          id: 'c',
          status: TransferStatus.completed,
          files: [_file('report.pdf', 1200000)],
          progress: 1,
        ),
      ]);
      await _capture(tester,
          state: state,
          page: const HomePage(),
          mode: mode,
          name: 'home_sessions_$suffix');
    });

    testWidgets('receive QR ($suffix)', (tester) async {
      final state = await _makeState(tester);
      await _capture(
        tester,
        state: state,
        page: const ReceivePage(
          debugPayload: ConnectPayload(
            ip: '192.168.1.10',
            port: 53317,
            alias: 'Marmalade-Fox',
            fingerprint: 'self-fp',
            token: 'shot-token',
          ),
        ),
        mode: mode,
        name: 'receive_qr_$suffix',
      );
    });

    testWidgets('send radar ($suffix)', (tester) async {
      final state = await _makeState(tester);
      state.seedForScreenshots(peers: [
        _peer('Pixel 7', 'fp-a', verified: true),
        _peer('Anna-Book', 'fp-b'),
        _peer('Workshop PC', 'fp-c'),
      ]);
      await _capture(
        tester,
        state: state,
        page: SendPage(
          scannerBuilder: (_, __) => const ColoredBox(color: Colors.black),
        ),
        mode: mode,
        name: 'send_radar_$suffix',
      );
    });

    testWidgets('consent sheet ($suffix)', (tester) async {
      const boundaryKey = Key('shot-boundary');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: EmberTheme.light(),
          darkTheme: EmberTheme.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ConsentSheet(
                data: const ConsentRequestData(
                  senderName: 'Pixel 7',
                  fileCount: 14,
                  totalSize: '45 MB',
                  verified: true,
                  previewFileNames: [
                    'IMG_2041.jpg',
                    'IMG_2042.jpg',
                    'holiday.mp4',
                  ],
                ),
                onAccept: () {},
                onDecline: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$_outDir/consent_sheet_$suffix.png')
          ..createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
