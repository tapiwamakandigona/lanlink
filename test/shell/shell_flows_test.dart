// Widget tests for the v4 app shell: first-run gate, home sessions,
// receive QR, send radar + Direct Link, and the consent sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/app.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/shell/first_run_page.dart';
import 'package:lanlink/ui/shell/home_page.dart';
import 'package:lanlink/ui/shell/receive_page.dart';
import 'package:lanlink/ui/shell/send_page.dart';
import 'package:lanlink/ui/v4/v4.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Device _peer({
  String alias = 'Pixel',
  String fingerprint = 'peer-fp',
  String deviceType = 'mobile',
}) =>
    Device(
      alias: alias,
      version: '2.1',
      deviceModel: 'Pixel',
      deviceType: deviceType,
      fingerprint: fingerprint,
      port: 53317,
      protocol: 'http',
      ip: '192.168.1.20',
    );

FileInfo _file(String name, {int size = 1024}) => FileInfo(
      id: 'id-$name',
      fileName: name,
      size: size,
      fileType: fileTypeForName(name),
      localPath: '/tmp/$name',
    );

TransferSession _session({
  required String id,
  TransferStatus status = TransferStatus.transferring,
  Device? peer,
  String? groupId,
  List<FileInfo>? files,
}) {
  final fs = files ?? [_file('$id.jpg')];
  final s = TransferSession(
    sessionId: id,
    direction: TransferDirection.send,
    peer: peer ?? _peer(),
    files: {for (final f in fs) f.id: FileProgress(file: f, status: status)},
    status: status,
  );
  s.groupId = groupId;
  return s;
}

/// Records calls instead of touching the network.
class _FakeSender extends Sender {
  _FakeSender({this.probeResult})
      : super(localDeviceProvider: () => _peer(alias: 'Self'));

  final Device? probeResult;
  final List<String> probedHosts = [];
  final List<Device> sentTo = [];

  @override
  Future<Device?> probe(Device peer) async {
    probedHosts.add('${peer.ip}:${peer.port}');
    return probeResult;
  }

  @override
  Future<void> send({
    required TransferSession session,
    required Device peer,
    required List<FileInfo> files,
  }) async {
    sentTo.add(peer);
  }
}

Future<AppState> _makeState(WidgetTester tester,
    {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({
    'lanlink_alias': 'Marmalade-Fox',
    'lanlink_last_onboarded_version': 'v4',
    'lanlink_connectivity_default_applied_v1': true,
    ...prefs,
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

  group('first run gate', () {
    testWidgets('first launch shows one name screen, then home',
        (tester) async {
      final state = await _makeState(tester,
          prefs: {'lanlink_last_onboarded_version': ''});
      await tester.pumpWidget(LanLinkApp(state: state));
      await tester.pump();

      expect(find.byType(FirstRunPage), findsOneWidget);
      // Prefilled with the alias-producing settings value.
      expect(find.widgetWithText(TextField, 'Marmalade-Fox'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Kitchen laptop');
      await tester.tap(find.text('Get started'));
      // PackageInfo does real file IO on desktop; let it complete.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
      expect(state.settings.alias, 'Kitchen laptop');
      expect(state.settings.lastOnboardedVersion, isNotEmpty);
    });

    testWidgets('returning users go straight to home', (tester) async {
      final state = await _makeState(tester);
      await tester.pumpWidget(LanLinkApp(state: state));
      await tester.pump();
      expect(find.byType(FirstRunPage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Receive'), findsOneWidget);
    });
  });

  group('home sessions', () {
    testWidgets('groups sessions by groupId and renders live progress',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = await _makeState(tester);
      state.seedForScreenshots(sessions: [
        _session(id: 'a', groupId: 'g1'),
        _session(id: 'b', groupId: 'g1'),
        _session(id: 'c', status: TransferStatus.completed),
      ]);
      await tester.pumpWidget(_wrap(state, const HomePage()));
      await tester.pump();

      expect(find.byType(SessionCard), findsNWidgets(3));
      // The g1 cluster reads as one visual unit with a group header.
      expect(find.text('To Pixel · 2 transfers'), findsOneWidget);
      // Terminal card shows the Sent! chip.
      expect(find.text('Sent!'), findsOneWidget);
    });

    testWidgets('dismiss hides a terminal card; Clear finished clears all',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = await _makeState(tester);
      state.seedForScreenshots(sessions: [
        _session(id: 'done1', status: TransferStatus.completed),
        _session(id: 'done2', status: TransferStatus.cancelled),
      ]);
      await tester.pumpWidget(_wrap(state, const HomePage()));
      await tester.pump();
      expect(find.byType(SessionCard), findsNWidgets(2));

      await tester.tap(find.text('Dismiss').first);
      await tester.pumpAndSettle();
      expect(find.byType(SessionCard), findsOneWidget);
      expect(state.visibleSessions, hasLength(1));

      await tester.tap(find.text('Clear finished'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionCard), findsNothing);
      expect(state.visibleSessions, isEmpty);
    });

    testWidgets('Stop on a live card cancels the session', (tester) async {
      final state = await _makeState(tester);
      final live = _session(id: 'live');
      state.seedForScreenshots(sessions: [live]);
      await tester.pumpWidget(_wrap(state, const HomePage()));
      await tester.pump();

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(live.status, TransferStatus.cancelled);
    });
  });

  group('receive page', () {
    testWidgets('renders a QR carrying the connect token and direct link',
        (tester) async {
      final state = await _makeState(tester);
      const payload = ConnectPayload(
        ip: '192.168.1.10',
        port: 53317,
        alias: 'Marmalade-Fox',
        fingerprint: 'self',
        token: 'tok-123',
      );
      await tester.pumpWidget(
          _wrap(state, const ReceivePage(debugPayload: payload)));
      await tester.pump();

      expect(find.byType(QrImageView), findsOneWidget);
      final panel =
          tester.widget<QrDisplayPanel>(find.byType(QrDisplayPanel));
      expect(panel.payload, contains('t=tok-123'));
      expect(panel.payload, contains('192.168.1.10'));
      // Direct Link fallback shows host:port.
      expect(find.textContaining('192.168.1.10:53317'), findsOneWidget);
    });
  });

  group('send page', () {
    Widget fakeScanner(BuildContext context, void Function(String) onRaw) =>
        const ColoredBox(color: Color(0xFF000000));

    testWidgets('radar shows peers with VerifiedBadge only for pinned ones',
        (tester) async {
      final state = await _makeState(tester);
      await tester.runAsync(() => state.settings.pinFingerprint('fp-a'));
      state.debugPeerSeen(_peer(alias: 'Purple-Otter', fingerprint: 'fp-a'));
      state.debugPeerSeen(_peer(alias: 'Stranger', fingerprint: 'fp-b'));

      await tester.pumpWidget(
          _wrap(state, SendPage(scannerBuilder: fakeScanner)));
      await tester.pump();

      expect(find.text('Purple-Otter'), findsOneWidget);
      expect(find.text('Stranger'), findsOneWidget);
      expect(find.byType(VerifiedBadge), findsOneWidget);
      expect(find.text('Scan their code'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // dispose rescan timer
    });

    testWidgets('Direct Link submit probes host:port and sends staged files',
        (tester) async {
      final state = await _makeState(tester);
      final fake = _FakeSender(probeResult: _peer(fingerprint: 'fp-direct'));
      state.debugInstallSender(fake);

      await tester.pumpWidget(_wrap(
        state,
        SendPage(
          scannerBuilder: fakeScanner,
          prestagedFiles: [_file('photo.jpg')],
        ),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '192.168.1.20:53317');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(fake.probedHosts, ['192.168.1.20:53317']);
      // Successful probe pins the fingerprint (Direct Link => verified).
      expect(state.settings.isPinned('fp-direct'), isTrue);
      // The staged file went straight into a send session.
      expect(state.visibleSessions, hasLength(1));
      expect(fake.sentTo.single.fingerprint, 'fp-direct');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('scanned QR with a token redeems it via connectWithToken',
        (tester) async {
      final state = await _makeState(tester);
      final redeemed = <String>[];
      final fake = _TokenSender(onToken: redeemed.add);
      state.debugInstallSender(fake);

      late void Function(String) emitRaw;
      Widget scanner(BuildContext context, void Function(String) onRaw) {
        emitRaw = onRaw;
        return const ColoredBox(color: Color(0xFF000000));
      }

      await tester.pumpWidget(_wrap(
        state,
        SendPage(scannerBuilder: scanner, prestagedFiles: [_file('a.txt')]),
      ));
      await tester.pump();
      await tester.tap(find.text('Scan their code'));
      await tester.pump();

      const payload = ConnectPayload(
        ip: '192.168.1.30',
        port: 53317,
        alias: 'Pixel',
        token: 'one-time',
      );
      emitRaw(payload.toQrString());
      await tester.pumpAndSettle();

      expect(redeemed, ['one-time']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('consent sheet', () {
    testWidgets('incoming prompt shows ConsentSheet; Accept takes all files',
        (tester) async {
      final state = await _makeState(tester);
      await tester.runAsync(() => state.settings.pinFingerprint('peer-fp'));
      state.debugPeerSeen(_peer());
      await tester.pumpWidget(LanLinkApp(state: state));
      await tester.pump();

      final files = [_file('holiday.mp4'), _file('notes.txt')];
      final future = state.debugTriggerIncomingPrompt(_peer(), files);
      await tester.pumpAndSettle();

      expect(find.byType(ConsentSheet), findsOneWidget);
      expect(find.textContaining('wants to send you 2 files'), findsOneWidget);
      expect(find.text('holiday.mp4'), findsOneWidget);
      // Pinned sender => verified badge on the sheet.
      expect(find.byType(VerifiedBadge), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      final decision = await future;
      expect(decision.reject, isFalse);
      expect(decision.fileIdsToAccept, {for (final f in files) f.id});
    });

    testWidgets('Decline rejects the transfer', (tester) async {
      final state = await _makeState(tester);
      await tester.pumpWidget(LanLinkApp(state: state));
      await tester.pump();

      final future =
          state.debugTriggerIncomingPrompt(_peer(), [_file('x.bin')]);
      await tester.pumpAndSettle();
      expect(find.byType(ConsentSheet), findsOneWidget);
      expect(find.byType(VerifiedBadge), findsNothing);

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      final decision = await future;
      expect(decision.reject, isTrue);
    });
  });
}

class _TokenSender extends Sender {
  _TokenSender({required this.onToken})
      : super(localDeviceProvider: () => _peer(alias: 'Self'));

  final void Function(String token) onToken;

  @override
  Future<Device?> connectWithToken(Device peer, String token) async {
    onToken(token);
    return peer.copyWith(verified: false);
  }

  @override
  Future<void> send({
    required TransferSession session,
    required Device peer,
    required List<FileInfo> files,
  }) async {}
}
