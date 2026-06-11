// TEMPORARY — screenshot generator for Slack previews. Not committed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/theme/app_theme.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/simple/simple_home_page.dart';
import 'package:lanlink/ui/simple/simple_receive_dialog.dart';
import 'package:lanlink/ui/simple/simple_saved_page.dart';
import 'package:lanlink/ui/simple/simple_send_flow.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fontDir =
    '/work/temp/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadFonts() async {
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
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

Device _peer(String alias) => Device(
      alias: alias,
      version: '2.1',
      deviceModel: 'Pixel 7',
      deviceType: 'mobile',
      fingerprint: 'fp-$alias',
      port: 53317,
      protocol: 'https',
      ip: '192.168.1.23',
    );

FileInfo _photo(String name, int size) => FileInfo(
      id: name,
      fileName: name,
      size: size,
      fileType: fileTypeForName(name),
    );

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'lanlink_alias': "Gogo's tablet",
      'lanlink_simple_mode_v1': true,
      'lanlink_simple_exit_button_v1': true,
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

  testWidgets('home', (tester) async {
    phone(tester);
    late AppState state;
    await tester.runAsync(() async {
      await _loadFonts();
      state = AppState.forScreenshots(settings: await AppSettings.load());
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: state.settings),
        ],
        child: _wrap(const SimpleHomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'simple_home');
  });

  testWidgets('receive prompt', (tester) async {
    phone(tester);
    await tester.runAsync(_loadFonts);
    await tester.pumpWidget(_wrap(Builder(builder: (context) {
      return Scaffold(
        body: Center(
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.transparent),
            onPressed: () => showSimpleReceivePrompt(
              context: context,
              peer: _peer("Rudo's phone"),
              files: [
                _photo('a.jpg', 2000000),
                _photo('b.jpg', 2000000),
                _photo('c.jpg', 2000000),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      );
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await shoot(tester, 'simple_receive_prompt');
  });

  testWidgets('sending progress', (tester) async {
    phone(tester);
    await tester.runAsync(_loadFonts);
    final files = [
      _photo('a.jpg', 3000000),
      _photo('b.jpg', 3000000),
      _photo('c.jpg', 3000000),
    ];
    final session = TransferSession(
      sessionId: 's1',
      direction: TransferDirection.send,
      peer: _peer("Rudo's phone"),
      files: {
        for (final f in files)
          f.id: FileProgress(file: f, bytes: (f.size * 0.65).round()),
      },
    );
    await tester.pumpWidget(_wrap(SimpleSendProgressPage(
      session: session,
      peerDisplayName: "Rudo's phone",
    )));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'simple_sending');
  });

  testWidgets('sent', (tester) async {
    phone(tester);
    await tester.runAsync(_loadFonts);
    final files = [
      _photo('a.jpg', 3000000),
      _photo('b.jpg', 3000000),
      _photo('c.jpg', 3000000),
    ];
    final session = TransferSession(
      sessionId: 's2',
      direction: TransferDirection.send,
      peer: _peer("Rudo's phone"),
      files: {
        for (final f in files)
          f.id: FileProgress(
            file: f,
            bytes: f.size,
            status: TransferStatus.completed,
          ),
      },
      status: TransferStatus.completed,
    );
    await tester.pumpWidget(_wrap(SimpleSendProgressPage(
      session: session,
      peerDisplayName: "Rudo's phone",
    )));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'simple_sent');
  });

  testWidgets('all saved', (tester) async {
    phone(tester);
    await tester.runAsync(_loadFonts);
    final files = [
      _photo('a.jpg', 3000000),
      _photo('b.jpg', 3000000),
      _photo('c.jpg', 3000000),
    ];
    final session = TransferSession(
      sessionId: 's3',
      direction: TransferDirection.receive,
      peer: _peer("Rudo's phone"),
      files: {
        for (final f in files)
          f.id: FileProgress(
            file: f,
            bytes: f.size,
            status: TransferStatus.completed,
            savedPath: '/home/gogo/Downloads/LanLink/${f.fileName}',
          ),
      },
      status: TransferStatus.completed,
    )..finishedAt = DateTime.now();
    await tester.pumpWidget(_wrap(SimpleSavedPage(session: session)));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'simple_saved');
  });
}
