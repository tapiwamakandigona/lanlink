// Widget tests for the Connect-to-PC UX frictions (U1–U3):
//  U1 the Tier-1 join wait is cancellable (no minutes-long spinner lock),
//  U2 the post-join probe polls instead of one fixed-delay shot, failing
//     loudly with a Retry,
//  U3 returning from the Tier-2/3 Settings hand-off re-checks the pending
//     target instead of dropping the flow silently.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/platform/wifi_joiner.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/shell/send_page.dart';
import 'package:lanlink/ui/v4/direct_connect/connect_router.dart';
import 'package:lanlink/ui/v4/v4.dart';
import 'package:provider/provider.dart';
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
      ip: '192.168.49.1',
    );

FileInfo _file(String name) => FileInfo(
      id: 'id-$name',
      fileName: name,
      size: 1024,
      fileType: fileTypeForName(name),
      localPath: '/tmp/$name',
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
    required session,
    required Device peer,
    required List<FileInfo> files,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hotspotQr = ConnectPayload(
    ip: '192.168.49.1',
    port: 53317,
    alias: 'Pixel',
    fingerprint: 'peer-fp',
    token: 'one-time',
    ssid: 'AndroidShare_1234',
    password: 'p4ssw0rd',
  );

  late void Function(String) emitRaw;
  Widget scanner(BuildContext context, void Function(String) onRaw) {
    emitRaw = onRaw;
    return const ColoredBox(color: Color(0xFF000000));
  }

  /// Pumps a SendPage wired with [router], opens the scanner and emits the
  /// hotspot QR, then flushes the async routing with bounded pumps (never
  /// pumpAndSettle: spinners animate forever).
  Future<void> scanHotspotQr(
    WidgetTester tester,
    AppState state,
    ConnectRouter router,
  ) async {
    await tester.pumpWidget(_wrap(
      state,
      SendPage(
        scannerBuilder: scanner,
        connectRouter: router,
        prestagedFiles: [_file('a.txt')],
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Scan their code'));
    await tester.pump();
    emitRaw(hotspotQr.toQrString());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('U1: cancellable Tier-1 join wait', () {
    testWidgets(
        'Cancel shows during the join wait; tapping it abandons the join, '
        'releases the platform request and opens the fallback sheet',
        (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = true;
      final leaves = <void>[];
      WifiJoiner.debugLeave = () async => leaves.add(null);
      addTearDown(() {
        WifiJoiner.debugAddNetworksSupportedOverride = null;
        WifiJoiner.debugLeave = null;
      });
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      // A join that hangs like the real system dialog can (~60 s + retry).
      final joinGate = Completer<WifiJoinResult>();
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) => joinGate.future,
      );

      await scanHotspotQr(tester, state, router);

      // The wait is on: dialog guidance + a Cancel affordance.
      expect(find.textContaining('connection dialog'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      // Flush the cancel race + the sheet's open animation.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      // Tier-2/3 options surface immediately — no waiting out the join.
      expect(
        find.textContaining('Couldn\'t join "AndroidShare_1234"'),
        findsOneWidget,
      );
      expect(find.text('Add network for me'), findsOneWidget);
      expect(find.text('Open Wi-Fi settings'), findsOneWidget);
      // The pending platform request was released (aborts the dialog).
      expect(leaves, hasLength(1));
      expect(redeemed, isEmpty);

      // A late "connected" from the abandoned attempt must be ignored AND
      // its process binding released — never silently kept.
      joinGate.complete(WifiJoinResult.connected);
      await tester.pump(const Duration(milliseconds: 100));
      expect(leaves, hasLength(2));
      expect(redeemed, isEmpty, reason: 'abandoned join must not connect');

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('U2: post-join readiness poll', () {
    testWidgets(
        'slow DHCP: the poll retries until the peer answers, then '
        'the token redeem runs', (tester) async {
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      var probes = 0;
      final router = ConnectRouter(
        // Routing probe fails; after the join the network needs ~3 s of
        // DHCP before the peer answers (poll succeeds on its 4th try).
        probe: (ip, port, timeout) async => ++probes >= 5,
        joinHotspot: (ssid, pass) async => WifiJoinResult.connected,
      );

      await scanHotspotQr(tester, state, router);
      // Poll in progress: progress text visible, no silent death.
      expect(find.textContaining('waiting for the network'), findsOneWidget);

      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));

      expect(probes, greaterThanOrEqualTo(5));
      expect(redeemed, ['one-time']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'poll exhaustion fails loudly with a Retry that re-runs the '
        'connect', (tester) async {
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      var reachable = false;
      var probes = 0;
      final router = ConnectRouter(
        probe: (ip, port, timeout) async {
          probes++;
          return reachable;
        },
        joinHotspot: (ssid, pass) async => WifiJoinResult.connected,
      );

      await scanHotspotQr(tester, state, router);
      // Exhaust the ~12 s poll budget.
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(redeemed, isEmpty);
      expect(find.textContaining("isn't answering yet"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      final probesBeforeRetry = probes;

      // The network came up while the error was on screen — Retry works.
      reachable = true;
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 1));

      expect(probes, greaterThan(probesBeforeRetry));
      expect(redeemed, ['one-time']);
      expect(find.text('Retry'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('U3: resume after the Settings hand-off', () {
    testWidgets(
        'coming back to the app re-checks the pending target and resumes '
        'the connect when it became reachable', (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = false;
      addTearDown(() => WifiJoiner.debugAddNetworksSupportedOverride = null);
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      var reachable = false;
      final router = ConnectRouter(
        // Small latency like a real socket attempt, so intermediate UI
        // ("Checking connection…") gets a frame to render.
        probe: (ip, port, timeout) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return reachable;
        },
        joinHotspot: (ssid, pass) async => WifiJoinResult.declinedOrUnavailable,
      );

      await scanHotspotQr(tester, state, router);
      await tester.tap(find.text('Open Wi-Fi settings'));
      await tester.pump(const Duration(milliseconds: 400));
      // The user stays out in Settings past the whole 90 s probe window —
      // the wait exhausts and leaves an error behind.
      for (var i = 0; i < 46; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      expect(find.textContaining("Still can't reach"), findsOneWidget);
      expect(redeemed, isEmpty);

      // They joined the network by hand, then switch back to LanLink.
      reachable = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Checking connection…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 1));

      expect(redeemed, ['one-time'],
          reason: 'resume must pick the flow back up, not drop it silently');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'still unreachable on resume: the fallback sheet re-opens with '
        'guidance instead of a dead end', (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = false;
      addTearDown(() => WifiJoiner.debugAddNetworksSupportedOverride = null);
      final state = await _makeState(tester);
      state.debugInstallSender(_TokenSender(onToken: (_) {}));
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.declinedOrUnavailable,
      );

      await scanHotspotQr(tester, state, router);
      await tester.tap(find.text('Open Wi-Fi settings'));
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 46; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      expect(find.textContaining("Still can't reach"), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Checking connection…'), findsOneWidget);
      // Exhaust the short resume re-check (~8 s at 1 s intervals).
      for (var i = 0; i < 9; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('Couldn\'t join "AndroidShare_1234"'),
        findsOneWidget,
        reason: 'unreachable on resume re-offers the fallback options',
      );
      // Dismissing the sheet clears the pending target: a second resume
      // must not nag with another re-check.
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 400));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Checking connection…'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
