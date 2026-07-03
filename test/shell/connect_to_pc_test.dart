// Widget tests for the Windows "Connect to phone" flow: the home-screen
// entry point (Windows-only) and ReceivePage opening straight into
// "No shared Wi-Fi" hosting via `initialMode`. All hotspot platform
// calls are faked — no test ever touches a real method channel.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/platform/local_hotspot.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/shell/home_page.dart';
import 'package:lanlink/ui/shell/receive_page.dart';
import 'package:lanlink/ui/v4/direct_connect/hotspot_creds_panel.dart';
import 'package:lanlink/ui/v4/direct_connect/hotspot_host_controller.dart';
import 'package:lanlink/ui/v4/direct_connect/network_mode_switch.dart';
import 'package:lanlink/ui/v4/v4.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hotspotInfo = HotspotInfo(
  ssid: 'LANLINK-PC',
  password: 'w1nd0ws-pass',
  hostIps: ['192.168.137.1'],
);

const _debugPayload = ConnectPayload(
  ip: '192.168.1.10',
  port: 53317,
  alias: 'Marmalade-Fox',
  fingerprint: 'self',
  token: 'tok-123',
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

/// A controller whose platform calls are fully faked and recorded.
HotspotHostController _fakeController(List<String> log) =>
    HotspotHostController(
      isSupported: () async {
        log.add('isSupported');
        return true;
      },
      hasPermission: () async {
        log.add('hasPermission');
        return true;
      },
      requestPermission: () async {
        log.add('requestPermission');
        return true;
      },
      start: () async {
        log.add('start');
        return _hotspotInfo;
      },
      stop: () async => log.add('stop'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('home "Connect to phone" entry point', () {
    testWidgets('is shown on Windows below the two verbs', (tester) async {
      final state = await _makeState(tester);
      await tester.pumpWidget(_wrap(state, const HomePage()));
      await tester.pump();

      expect(find.byType(TwoVerbHome), findsOneWidget);
      expect(find.text('Connect to phone'), findsOneWidget);
      expect(
        find.textContaining('Link a phone straight to this PC'),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('is absent everywhere else', (tester) async {
      final state = await _makeState(tester);
      await tester.pumpWidget(_wrap(state, const HomePage()));
      await tester.pump();

      expect(find.text('Connect to phone'), findsNothing,
          reason: 'no entry point expected on $defaultTargetPlatform');
    },
        variant: const TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
          TargetPlatform.linux,
        }));

    testWidgets('tap opens Receive with "No shared Wi-Fi" pre-selected',
        (tester) async {
      // Scope: navigation + initialMode preselection only. Hosting is NOT
      // exercised here — the tile constructs a real HotspotHostController
      // whose isSupported gates on dart:io Platform, which is false on the
      // test host. Auto-hosting, QR contents, and teardown are covered by
      // the debugHotspotController tests below.
      final state = await _makeState(tester);
      await tester.pumpWidget(_wrap(state, const HomePage()));
      await tester.pump();

      await tester.tap(find.text('Connect to phone'));
      await tester.pumpAndSettle();

      expect(find.byType(ReceivePage), findsOneWidget);
      final page = tester.widget<ReceivePage>(find.byType(ReceivePage));
      expect(page.initialMode, NetworkMode.directLink);
      final modeSwitch = tester
          .widget<NetworkModeSwitch>(find.byType(NetworkModeSwitch));
      expect(modeSwitch.mode, NetworkMode.directLink,
          reason: '"No shared Wi-Fi" should be the selected mode');
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('ReceivePage initialMode', () {
    testWidgets('defaults to Same Wi-Fi and starts nothing', (tester) async {
      final state = await _makeState(tester);
      final log = <String>[];
      final controller = _fakeController(log);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(
        state,
        ReceivePage(
          debugPayload: _debugPayload,
          debugHotspotController: controller,
        ),
      ));
      await tester.pumpAndSettle();

      expect(log, isEmpty);
      expect(controller.phase, HotspotHostPhase.idle);
      expect(find.byType(HotspotCredsPanel), findsNothing);
    });

    testWidgets(
        'directLink pre-selects "No shared Wi-Fi" and hosts without a tap; '
        'QR carries ssid & pass', (tester) async {
      final state = await _makeState(tester);
      final log = <String>[];
      final controller = _fakeController(log);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(
        state,
        ReceivePage(
          initialMode: NetworkMode.directLink,
          debugPayload: _debugPayload,
          debugHotspotController: controller,
        ),
      ));
      await tester.pumpAndSettle();

      expect(log, contains('start'));
      expect(controller.phase, HotspotHostPhase.running);
      final panel = tester.widget<QrDisplayPanel>(find.byType(QrDisplayPanel));
      expect(panel.payload, startsWith('lanlink://connect'));
      expect(panel.payload, contains('ssid=LANLINK-PC'));
      expect(panel.payload, contains('pass=w1nd0ws-pass'));
      // Hotspot interface address replaces the LAN one.
      expect(panel.payload, contains('192.168.137.1'));
      expect(find.byType(HotspotCredsPanel), findsOneWidget);
    });

    testWidgets('flipping back to Same Wi-Fi still tears down',
        (tester) async {
      final state = await _makeState(tester);
      final log = <String>[];
      final controller = _fakeController(log);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(
        state,
        ReceivePage(
          initialMode: NetworkMode.directLink,
          debugPayload: _debugPayload,
          debugHotspotController: controller,
        ),
      ));
      await tester.pumpAndSettle();
      expect(controller.isRunning, isTrue);

      await tester.tap(find.text('Same Wi-Fi'));
      await tester.pumpAndSettle();

      expect(log.last, 'stop');
      expect(controller.phase, HotspotHostPhase.idle);
      expect(find.byType(HotspotCredsPanel), findsNothing);
    });
  });

  group('hotspot creds panel copy', () {
    testWidgets('reads for phone guests when a Windows PC hosts',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: EmberTheme.light(),
        home: const Scaffold(
          body: HotspotCredsPanel(ssid: 'LANLINK-PC', password: 'pw'),
        ),
      ));

      expect(
        find.text("Phone won't scan? Join this Wi-Fi from it, then scan."),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('keeps the phone-host copy on Android', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: EmberTheme.light(),
        home: const Scaffold(
          body: HotspotCredsPanel(ssid: 'AndroidShare_1234', password: 'pw'),
        ),
      ));

      expect(
        find.text('iPhone or computer? Join this Wi-Fi first, then scan.'),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
