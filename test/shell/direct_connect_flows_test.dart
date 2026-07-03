// Widget tests for Direct Connect (F1): the receive-side network mode
// switch + hotspot hosting, and the send-side smart routing after a scan.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/platform/local_hotspot.dart';
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
          return true;
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
          return true;
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

    testWidgets('failed join shows manual instructions and stops',
        (tester) async {
      final state = await _makeState(tester);
      final redeemed = <String>[];
      state.debugInstallSender(_TokenSender(onToken: redeemed.add));
      final router = ConnectRouter(
        probe: (ip, port, timeout) async => false,
        joinHotspot: (ssid, pass) async => false,
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
      // Not pumpAndSettle: the error state leaves the live camera frame
      // up, which never settles. Two pumps flush the async error path.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(redeemed, isEmpty);
      expect(
        find.textContaining('Could not join "AndroidShare_1234"'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
