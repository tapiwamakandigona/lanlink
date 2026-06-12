import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/platform/local_hotspot.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/theme/app_theme.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/simple/connect/host_hotspot_page.dart';
import 'package:lanlink/ui/simple/connect/receive_qr_page.dart';
import 'package:lanlink/ui/simple/connect/send_connect_page.dart';
import 'package:lanlink/ui/simple/connect/simple_session_page.dart';
import 'package:lanlink/ui/simple/simple_home_page.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Device _peer({String alias = 'Pixel', String fingerprint = 'peer-fp'}) =>
    Device(
      alias: alias,
      version: '2.1',
      deviceModel: 'Pixel',
      deviceType: 'mobile',
      fingerprint: fingerprint,
      port: 53317,
      protocol: 'http',
      ip: '192.168.1.20',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'lanlink_alias': 'Test phone',
      'lanlink_simple_mode_v1': true,
      'lanlink_connectivity_default_applied_v1': true,
    });
  });

  Future<AppState> makeState(WidgetTester tester) async {
    late AppState state;
    await tester.runAsync(() async {
      state = AppState.forScreenshots(settings: await AppSettings.load());
    });
    return state;
  }

  Widget wrap(AppState state, Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: state.settings),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );
  }

  group('SimpleHomePage (connect-first)', () {
    testWidgets('offers Send, Receive and Connect to a computer',
        (tester) async {
      final state = await makeState(tester);
      await tester.pumpWidget(wrap(state, const SimpleHomePage()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Receive'), findsOneWidget);
      expect(find.text('Connect to a computer'), findsOneWidget);
    });
  });

  group('ReceiveQrPage', () {
    testWidgets('shows the QR and waiting state', (tester) async {
      final state = await makeState(tester);
      const payload = ConnectPayload(
        ip: '192.168.1.10',
        port: 53317,
        alias: 'Test phone',
        fingerprint: 'self',
      );
      await tester.pumpWidget(
        wrap(state, const ReceiveQrPage(debugPayload: payload)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Show this code to the sender'), findsOneWidget);
      expect(find.textContaining('Waiting for them to scan'), findsOneWidget);
    });

    testWidgets('navigates to the session when a sender registers',
        (tester) async {
      final state = await makeState(tester);
      const payload = ConnectPayload(
        ip: '192.168.1.10',
        port: 53317,
        alias: 'Test phone',
      );
      await tester.pumpWidget(
        wrap(state, const ReceiveQrPage(debugPayload: payload)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      state.seedForScreenshots(peers: [_peer()]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SimpleSessionPage), findsOneWidget);
      expect(find.text('Connected to Pixel'), findsOneWidget);
    });
  });

  group('SendConnectPage', () {
    Widget fakeScanner(BuildContext context, void Function(String) onRaw) =>
        const ColoredBox(color: Colors.black);

    testWidgets('shows scanner area and searching state', (tester) async {
      final state = await makeState(tester);
      await tester.pumpWidget(
        wrap(state, SendConnectPage(scannerBuilder: fakeScanner)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Looking for nearby devices'), findsOneWidget);
      expect(find.text('or tap a nearby device'), findsOneWidget);
      expect(find.text('No Wi-Fi here? Host a hotspot'), findsOneWidget);
    });

    testWidgets('tapping a nearby device opens the session', (tester) async {
      final state = await makeState(tester);
      state.seedForScreenshots(peers: [_peer(alias: 'Laptop')]);
      await tester.pumpWidget(
        wrap(state, SendConnectPage(scannerBuilder: fakeScanner)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Laptop'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleSessionPage), findsOneWidget);
      expect(find.text('Connected to Laptop'), findsOneWidget);
    });

    testWidgets('pcMode shows computer-flavoured copy', (tester) async {
      final state = await makeState(tester);
      await tester.pumpWidget(
        wrap(state, SendConnectPage(pcMode: true, scannerBuilder: fakeScanner)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Connect to a computer'), findsOneWidget);
      expect(
          find.textContaining('Open LanLink on your computer'), findsOneWidget);
    });
  });

  group('HostHotspotPage', () {
    const info = HotspotInfo(
      ssid: 'AndroidShare_1234',
      password: 'secret123',
      hostIps: ['192.168.49.1'],
    );

    testWidgets('shows credentials in big text and a Wi-Fi QR', (tester) async {
      final state = await makeState(tester);
      await tester.pumpWidget(
        wrap(state, const HostHotspotPage(debugInfo: info)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('AndroidShare_1234'), findsOneWidget);
      expect(find.text('secret123'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
          find.textContaining('Waiting for the other device'), findsOneWidget);
    });

    testWidgets('navigates to the session when the device joins',
        (tester) async {
      final state = await makeState(tester);
      await tester.pumpWidget(
        wrap(state, const HostHotspotPage(debugInfo: info)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      state.seedForScreenshots(peers: [_peer(alias: 'Laptop')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SimpleSessionPage), findsOneWidget);
      expect(find.text('Connected to Laptop'), findsOneWidget);
    });
  });

  group('SimpleSessionPage', () {
    testWidgets('shows the link header and send buttons', (tester) async {
      final state = await makeState(tester);
      await tester.pumpWidget(
        wrap(
          state,
          SimpleSessionPage(peer: _peer(), peerDisplayName: 'Pixel'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Connected to Pixel'), findsOneWidget);
      expect(find.textContaining('Send'), findsWidgets);
      expect(find.textContaining('both ways'), findsOneWidget);
    });
  });
}
