// History rows must answer "what did I move, with whom, when" at a glance.
// Single-file rows name the file and show its type glyph; multi-file rows
// fall back to a count.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/history_page.dart';
import 'package:lanlink/ui/v4/v4.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Device _peer() => Device(
      alias: 'Purple-Otter',
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: 'fp-1',
      port: 53317,
      protocol: 'http',
      ip: '192.168.1.22',
    );

FileInfo _file(String name, {int size = 4 * 1024 * 1024}) => FileInfo(
      id: name,
      fileName: name,
      size: size,
      fileType: 'other',
    );

TransferSession _session(
  String id,
  List<FileInfo> files, {
  TransferDirection direction = TransferDirection.receive,
  TransferStatus status = TransferStatus.completed,
}) =>
    TransferSession(
      sessionId: id,
      direction: direction,
      peer: _peer(),
      files: {for (final f in files) f.id: FileProgress(file: f)},
      status: status,
    )..finishedAt = DateTime.now();

Future<AppState> _state(WidgetTester tester, List<TransferSession> s) async {
  SharedPreferences.setMockInitialValues({'lanlink_alias': 'Marmalade-Fox'});
  late AppState state;
  await tester.runAsync(() async {
    state = AppState.forScreenshots(settings: await AppSettings.load());
  });
  state.seedForScreenshots(peers: [_peer()], sessions: s);
  return state;
}

Widget _host(AppState state) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: state.settings),
      ],
      child: MaterialApp(theme: EmberTheme.light(), home: const HistoryPage()),
    );

void main() {
  testWidgets('single-file row names the file and shows its glyph',
      (tester) async {
    final state = await _state(tester, [
      _session('s1', [_file('holiday.mp4')])
    ]);
    await tester.pumpWidget(_host(state));
    await tester.pump();

    expect(find.textContaining('holiday.mp4'), findsOneWidget);
    expect(find.textContaining('1 file'), findsNothing);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.textContaining('Received • Purple-Otter'), findsOneWidget);
  });

  testWidgets('multi-file row falls back to a count, no glyph', (tester) async {
    final state = await _state(tester, [
      _session('s2', [_file('a.jpg'), _file('b.jpg'), _file('c.jpg')])
    ]);
    await tester.pumpWidget(_host(state));
    await tester.pump();

    expect(find.textContaining('3 files'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });

  testWidgets('empty history explains itself', (tester) async {
    final state = await _state(tester, const []);
    await tester.pumpWidget(_host(state));
    await tester.pump();

    expect(find.text('No completed transfers yet.'), findsOneWidget);
    // Nothing to clear, so no destructive affordance.
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
