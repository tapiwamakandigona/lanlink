// Widget tests for Direct Connect (F1): the receive-side network mode
// switch + hotspot hosting, and the send-side smart routing after a scan.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/platform/local_hotspot.dart';
import 'package:lanlink/core/platform/wifi_joiner.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/shell/receive_page.dart';
import 'package:lanlink/ui/shell/send_page.dart';
import 'package:lanlink/ui/v4/direct_connect/connect_router.dart';
import 'package:lanlink/ui/v4/direct_connect/hotspot_creds_panel.dart';
import 'package:lanlink/ui/v4/direct_connect/hotspot_host_controller.dart';
import 'package:lanlink/ui/v4/v4.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hotspotInfo = HotspotInfo(
  ssid: 'AndroidShare_1234',
  password: 'p4ssw0rd',
  hostIps: ['192.168.49.1'],
);

Device _peer({String alias = 'Pixel', String fingerprint = 'peer-fp'}) =>
    Device(
      alias: alias,
      version: '2.1',
      deviceModel: 'Pixel',
      deviceType: 'mobile',
      fingerprint: fingerprint,
      port: 53317,
      protocol: 'https',
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

/// A controller whose platform calls are fully faked and recorded.
HotspotHostController _fakeController(
  List<String> log, {
  bool permitted = true,
}) =>
    HotspotHostController(
      isSupported: () async => true,
      hasPermission: () async {
        log.add('hasPermission');
        return permitted;
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

  const debugPayload = ConnectPayload(
    ip: '192.168.1.10',
    port: 53317,
    alias: 'Marmalade-Fox',
    fingerprint: 'self',
    token: 'tok-123',
  );

  group('receive page network mode switch', () {
    testWidgets('defaults to Same Wi-Fi with today\'s QR flow', (tester) async {
      final state = await _makeState(tester);
      await tester.pumpWidget(
          _wrap(state, const ReceivePage(debugPayload: debugPayload)));
      await tester.pump();

      expect(find.text('Same Wi-Fi'), findsOneWidget);
      expect(find.text('No shared Wi-Fi'), findsOneWidget);
      expect(find.byType(QrDisplayPanel), findsOneWidget);
      expect(find.byType(HotspotCredsPanel), findsNothing);
      // Direct Link fallback of the LAN flow.
      expect(find.textContaining('192.168.1.10:53317'), findsOneWidget);
    });

    testWidgets(
        'flipping to No shared Wi-Fi starts the hotspot, bakes creds into '
        'the QR and shows manual-join details', (tester) async {
      final state = await _makeState(tester);
      final log = <String>[];
      final controller = _fakeController(log);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(
        state,
        ReceivePage(
          debugPayload: debugPayload,
          debugHotspotController: controller,
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('No shared Wi-Fi'));
      await tester.pumpAndSettle();

      expect(log, contains('start'));
      expect(controller.phase, HotspotHostPhase.running);
      final panel = tester.widget<QrDisplayPanel>(find.byType(QrDisplayPanel));
      expect(panel.payload, contains('ssid=AndroidShare_1234'));
      expect(panel.payload, contains('pass=p4ssw0rd'));
      // Hotspot interface address replaces the LAN one.
      expect(panel.payload, contains('192.168.49.1'));
      // Manual-join instructions for iPhone/desktop guests.
      expect(find.byType(HotspotCredsPanel), findsOneWidget);
      expect(find.text('AndroidShare_1234'), findsOneWidget);
      expect(find.text('p4ssw0rd'), findsOneWidget);
    });

    testWidgets('missing permission pauses with one Allow button',
        (tester) async {
      final state = await _makeState(tester);
      final log = <String>[];
      final controller = _fakeController(log, permitted: false);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(
        state,
        ReceivePage(
          debugPayload: debugPayload,
          debugHotspotController: controller,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('No shared Wi-Fi'));
      await tester.pumpAndSettle();

      expect(controller.phase, HotspotHostPhase.needsPermission);
      expect(log, isNot(contains('start')));

      await tester.tap(find.text('Allow and continue'));
      await tester.pumpAndSettle();
      expect(controller.phase, HotspotHostPhase.running);
      expect(find.byType(HotspotCredsPanel), findsOneWidget);
    });

    testWidgets('switching back to Same Wi-Fi tears the hotspot down',
        (tester) async {
      final state = await _makeState(tester);
      final log = <String>[];
      final controller = _fakeController(log);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(
        state,
        ReceivePage(
          debugPayload: debugPayload,
          debugHotspotController: controller,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('No shared Wi-Fi'));
      await tester.pumpAndSettle();
      expect(controller.isRunning, isTrue);

      await tester.tap(find.text('Same Wi-Fi'));
      await tester.pumpAndSettle();

      expect(log.last, 'stop');
      expect(controller.phase, HotspotHostPhase.idle);
      expect(find.byType(HotspotCredsPanel), findsNothing);
      final panel = tester.widget<QrDisplayPanel>(find.byType(QrDisplayPanel));
      expect(panel.payload, isNot(contains('ssid=')));
    });

    testWidgets('leaving the page closes the hotspot reservation',
        (tester) async {
      final state = await _makeState(tester);
      final log = <String>[];
      final controller = _fakeController(log);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(
        state,
        ReceivePage(
          debugPayload: debugPayload,
          debugHotspotController: controller,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('No shared Wi-Fi'));
      await tester.pumpAndSettle();
      expect(controller.isRunning, isTrue);

      await tester.pumpWidget(const SizedBox()); // pop / dispose
      await tester.pump();

      expect(log.last, 'stop');
      expect(controller.isRunning, isFalse);
    });
  });

  group('send page smart routing', () {
    late void Function(String) emitRaw;
    Widget scanner(BuildContext context, void Function(String) onRaw) {
      emitRaw = onRaw;
      return const ColoredBox(color: Color(0xFF000000));
    }

    const hotspotQr = ConnectPayload(
      ip: '192.168.49.1',
      port: 53317,
      alias: 'Pixel',
      fingerprint: 'peer-fp',
      token: 'one-time',
      ssid: 'AndroidShare_1234',
      password: 'p4ssw0rd',
    );

    testWidgets(
        'reachable peer connects directly — no hotspot join, normal v4 '
        'token redeem', (tester) async {
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      final joins = <String>[];
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => true,
        joinHotspot: (ssid, pass) async {
          joins.add(ssid);
          return WifiJoinResult.connected;
        },
      );

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
      await tester.pumpAndSettle();

      expect(joins, isEmpty);
      expect(redeemed, ['one-time']);
    });

    testWidgets(
        'unreachable peer + creds auto-joins, then runs the same v4 '
        'token redeem', (tester) async {
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      final joins = <String>[];
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async {
          joins.add('$ssid/$pass');
          return WifiJoinResult.connected;
        },
      );

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
      await tester.pumpAndSettle();

      expect(joins, ['AndroidShare_1234/p4ssw0rd']);
      // Security unchanged: the hotspot path still redeems the one-time
      // token (fingerprint pinning happens inside connectWithToken).
      expect(redeemed, ['one-time']);
    });

    /// Pumps a SendPage wired with [router], opens the scanner and emits
    /// the hotspot QR, then flushes the async routing with bounded pumps
    /// (never pumpAndSettle: the live camera frame animates forever).
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
      // Flush the probe/join future chain plus the sheet's open animation.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets(
        'failed join opens the fallback sheet: password, copy button and '
        'both actions when Add-networks is supported', (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = true;
      addTearDown(() => WifiJoiner.debugAddNetworksSupportedOverride = null);
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.declinedOrUnavailable,
      );

      await scanHotspotQr(tester, state, router);

      expect(redeemed, isEmpty, reason: 'no connect while the join failed');
      expect(
        find.textContaining('Couldn\'t join "AndroidShare_1234"'),
        findsOneWidget,
      );
      expect(find.text('p4ssw0rd'), findsOneWidget);
      expect(find.byTooltip('Copy password'), findsOneWidget);
      expect(find.text('Add network for me'), findsOneWidget);
      expect(find.text('Open Wi-Fi settings'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'Tier-2 action is hidden when the Add-networks panel is unsupported',
        (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = false;
      addTearDown(() => WifiJoiner.debugAddNetworksSupportedOverride = null);
      final state = await _makeState(tester);
      state.debugInstallSender(_TokenSender(onToken: (_) {}));
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.timeout,
      );

      await scanHotspotQr(tester, state, router);

      expect(find.text('Add network for me'), findsNothing);
      expect(find.text('Open Wi-Fi settings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('timeout reason reaches the sheet wording', (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = false;
      addTearDown(() => WifiJoiner.debugAddNetworksSupportedOverride = null);
      final state = await _makeState(tester);
      state.debugInstallSender(_TokenSender(onToken: (_) {}));
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.timeout,
      );

      await scanHotspotQr(tester, state, router);

      expect(find.textContaining('timed out'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cancelling the fallback sheet stops the flow — no connect',
        (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = false;
      addTearDown(() => WifiJoiner.debugAddNetworksSupportedOverride = null);
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.declinedOrUnavailable,
      );

      await scanHotspotQr(tester, state, router);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(redeemed, isEmpty);
      expect(find.text('Cancel'), findsNothing, reason: 'sheet dismissed');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'Tier 3: open Wi-Fi settings, probe loop turns reachable, connect '
        'resumes with the same token redeem', (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = false;
      addTearDown(() => WifiJoiner.debugAddNetworksSupportedOverride = null);
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      var probes = 0;
      final router = ConnectRouter(
        // First probe (smart routing) fails; the post-settings poll
        // succeeds — as if the user joined the network by hand.
        probe: (ip, port, timeout) async => ++probes > 1,
        joinHotspot: (ssid, pass) async => WifiJoinResult.declinedOrUnavailable,
      );

      await scanHotspotQr(tester, state, router);
      await tester.tap(find.text('Open Wi-Fi settings'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(probes, greaterThanOrEqualTo(2));
      expect(redeemed, ['one-time'],
          reason: 'reachable peer resumes the original connect flow');
    });

    testWidgets(
        'Tier 3 resume: the join is device-level, so leaving the page '
        'releases nothing (Disconnect contract)', (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = false;
      final leaves = <void>[];
      WifiJoiner.debugLeave = () async => leaves.add(null);
      addTearDown(() {
        WifiJoiner.debugAddNetworksSupportedOverride = null;
        WifiJoiner.debugLeave = null;
      });
      final state = await _makeState(tester);
      state.debugInstallSender(_TokenSender(onToken: (_) {}));
      var probes = 0;
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => ++probes > 1,
        joinHotspot: (ssid, pass) async => WifiJoinResult.declinedOrUnavailable,
      );

      await scanHotspotQr(tester, state, router);
      await tester.tap(find.text('Open Wi-Fi settings'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      // Pop the page without any hand-off: a Tier-1 join would release
      // its binding here, a Tier-2/3 join must not (there is none).
      await tester.pumpWidget(const SizedBox());

      expect(leaves, isEmpty,
          reason: 'Tier-2/3 joins have no process binding to release');
    });

    testWidgets(
        'Tier 2: Add-network save + probe loop resumes connect; retry '
        'ordering is join-first, fallback-second', (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = true;
      final added = <String>[];
      WifiJoiner.debugFallbackAddNetwork = (ssid, pass) async {
        added.add('$ssid/$pass');
        return true;
      };
      addTearDown(() {
        WifiJoiner.debugAddNetworksSupportedOverride = null;
        WifiJoiner.debugFallbackAddNetwork = null;
      });
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      final order = <String>[];
      var probes = 0;
      final router = ConnectRouter(
        probe: (ip, port, timeout) async {
          order.add('probe');
          return ++probes > 1;
        },
        joinHotspot: (ssid, pass) async {
          order.add('join');
          return WifiJoinResult.declinedOrUnavailable;
        },
      );

      await scanHotspotQr(tester, state, router);
      expect(added, isEmpty, reason: 'Tier 2 must wait for the user tap');
      await tester.tap(find.text('Add network for me'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(added, ['AndroidShare_1234/p4ssw0rd']);
      expect(redeemed, ['one-time']);
      // Tier-1 join ran (after the first probe) before any fallback probe.
      expect(order.take(2), ['probe', 'join']);
    });

    testWidgets(
        'Tier 2: user backing out of the save panel shows an error and '
        'does not connect', (tester) async {
      WifiJoiner.debugAddNetworksSupportedOverride = true;
      WifiJoiner.debugFallbackAddNetwork = (ssid, pass) async => false;
      addTearDown(() {
        WifiJoiner.debugAddNetworksSupportedOverride = null;
        WifiJoiner.debugFallbackAddNetwork = null;
      });
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => WifiJoinResult.declinedOrUnavailable,
      );

      await scanHotspotQr(tester, state, router);
      await tester.tap(find.text('Add network for me'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(redeemed, isEmpty);
      expect(find.textContaining("The network wasn't saved"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
