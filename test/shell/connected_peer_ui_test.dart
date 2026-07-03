// Widget tests for the F3 symmetric-session UI: the ConnectedPeerCard
// strip on home ("Send files" without re-scanning + Disconnect) and the
// LiveSessionCard subscription that keeps progress ticks page-local.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/shell/home_page.dart';
import 'package:lanlink/ui/widgets/connected_peer_card.dart';
import 'package:lanlink/ui/widgets/live_session_card.dart';
import 'package:lanlink/ui/v4/v4.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Device _peer(String alias, String fp) => Device(
      alias: alias,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: fp,
      port: 1234,
      protocol: 'https',
      ip: '192.168.1.20',
    );

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

Widget _wrap(AppState state, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: state.settings),
      ],
      child: MaterialApp(theme: EmberTheme.light(), home: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home shows a ConnectedPeerCard for each linked peer',
      (tester) async {
    final state = await _makeState(tester);
    state.seedForScreenshots(linkedPeers: [_peer('Basil-Otter', 'fp-x')]);

    await tester.pumpWidget(_wrap(state, const HomePage()));
    await tester.pump();

    expect(find.byType(ConnectedPeerCard), findsOneWidget);
    expect(find.text('Basil-Otter'), findsOneWidget);
    expect(find.text('Send files'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  testWidgets('Disconnect clears the strip and returns home to idle',
      (tester) async {
    final state = await _makeState(tester);
    state.seedForScreenshots(linkedPeers: [_peer('Basil-Otter', 'fp-x')]);

    await tester.pumpWidget(_wrap(state, const HomePage()));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Disconnect'));
    });
    await tester.pump();

    expect(find.byType(ConnectedPeerCard), findsNothing);
    expect(state.isLinked('fp-x'), isFalse);
    expect(state.isPeerDisconnected('fp-x'), isTrue,
        reason: 'the peer must re-pair before it can push again');
  });

  testWidgets(
      'LiveSessionCard repaints on progress ticks without an AppState notify',
      (tester) async {
    final state = await _makeState(tester);
    final file = FileInfo(
      id: 'f1',
      fileName: 'photo.jpg',
      size: 100,
      fileType: 'image',
    );
    final session = TransferSession(
      sessionId: 's1',
      direction: TransferDirection.send,
      peer: _peer('Basil-Otter', 'fp-x'),
      files: {'f1': FileProgress(file: file, bytes: 0)},
    );

    var stateNotifies = 0;
    state.addListener(() => stateNotifies++);
    await tester.pumpWidget(
        _wrap(state, LiveSessionCard(session: session, state: state)));
    expect(find.textContaining('photo.jpg'), findsOneWidget);

    session.updateBytes('f1', 50);
    await tester.pump();
    expect(find.byType(SessionCard), findsOneWidget,
        reason: 'the card itself must track the live session');
    expect(stateNotifies, 0,
        reason: 'a progress tick must stay local to the card');
  });
}
