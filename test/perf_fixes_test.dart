// Regression tests for the v4.1 perf-audit fixes (B2, B3, S4, N2).
//
// - B2: the receive QR is encoded once per payload string, not once per
//   rebuild (qrCodeForPayload memoization).
// - B3: MaterialApp keeps identical ThemeData instances across AppSettings
//   notifies that don't change the theme mode.
// - S4: SubnetScanner debounces full sweeps and can be paused while
//   transfers are active.
// - N2: the share-picker search filter is debounced (covered in
//   share_picker_test.dart; the timer plumbing is exercised there).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/app.dart';
import 'package:lanlink/core/discovery/subnet_scanner.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/v4/v4.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts probes without touching the network.
class _CountingSender extends Sender {
  _CountingSender()
      : super(
          localDeviceProvider: () => Device(
            alias: 'me',
            version: LanLinkProtocol.protocolVersion,
            deviceModel: 'test',
            deviceType: LanLinkProtocol.deviceTypeHeadless,
            fingerprint: 'me',
            port: LanLinkProtocol.defaultPort,
            protocol: 'https',
            ip: '127.0.0.1',
          ),
        );

  int probes = 0;

  @override
  Future<Device?> probe(
    Device peer, {
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    probes += 1;
    return null;
  }
}

/// The scanner's internal Future.wait snapshots the in-flight probe list, so
/// a few stragglers can still land shortly after [SubnetScanner.scan]
/// returns. Wait until the probe counter stops moving before asserting.
Future<int> _settledProbes(_CountingSender sender) async {
  var last = -1;
  while (sender.probes != last) {
    last = sender.probes;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return last;
}

SubnetScanner _scanner(_CountingSender sender,
    {Duration minScanInterval = const Duration(seconds: 20)}) {
  return SubnetScanner(
    sender: sender,
    onPeer: (_) {},
    parallelProbes: 64,
    perHostTimeout: const Duration(milliseconds: 50),
    minScanInterval: minScanInterval,
  );
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B2: QR payload memoization', () {
    test('same payload returns the identical QrCode instance', () {
      final a = qrCodeForPayload('lanlink://pair?x=1');
      final b = qrCodeForPayload('lanlink://pair?x=1');
      expect(identical(a, b), isTrue,
          reason: 'rebuilds must not re-encode the QR for the same payload');
    });

    test('different payloads produce different QrCode instances', () {
      final a = qrCodeForPayload('lanlink://pair?x=1');
      final b = qrCodeForPayload('lanlink://pair?x=2');
      expect(identical(a, b), isFalse);
    });

    testWidgets('QrDisplayPanel keeps rendering after parent rebuilds',
        (tester) async {
      const panel = QrDisplayPanel(
        payload: 'lanlink://pair?token=abc',
        deviceName: 'Marmalade-Fox',
      );
      await tester.pumpWidget(MaterialApp(
        theme: EmberTheme.light(),
        home: const Scaffold(body: Center(child: panel)),
      ));
      expect(find.text('Marmalade-Fox'), findsOneWidget);
      // Force a full rebuild of the parent; the panel must reuse the
      // memoized QrCode (identity checked above) and still render.
      await tester.pumpWidget(MaterialApp(
        theme: EmberTheme.light(),
        home: const Scaffold(body: Center(child: panel)),
      ));
      expect(find.text('Marmalade-Fox'), findsOneWidget);
    });
  });

  group('B3: theme memoization in LanLinkApp', () {
    testWidgets(
        'settings notifies that do not change themeMode keep identical '
        'ThemeData and do not rebuild MaterialApp', (tester) async {
      final state = await _makeState(tester);
      await tester.pumpWidget(LanLinkApp(state: state));
      await tester.pump();

      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      final before = app();
      final themeBefore = before.theme;
      final darkBefore = before.darkTheme;

      // A settings write unrelated to the theme (one of the 22 notify
      // sites the audit flagged).
      await tester.runAsync(
          () => state.settings.setNickname('some-fingerprint', 'Buddy'));
      await tester.pump();

      final after = app();
      expect(identical(before, after), isTrue,
          reason: 'MaterialApp must not rebuild on non-theme settings writes');
      expect(identical(themeBefore, after.theme), isTrue);
      expect(identical(darkBefore, after.darkTheme), isTrue);
    });

    testWidgets('changing the theme mode still retunes MaterialApp',
        (tester) async {
      final state = await _makeState(tester);
      await tester.pumpWidget(LanLinkApp(state: state));
      await tester.pump();

      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app().themeMode, ThemeMode.system);
      final themeBefore = app().theme;

      await tester.runAsync(() => state.settings.setThemeMode('dark'));
      await tester.pump();

      expect(app().themeMode, ThemeMode.dark);
      // The ThemeData instances themselves stay memoized even when the
      // mode flips — only the mode selection changes.
      expect(identical(app().theme, themeBefore), isTrue);
    });
  });

  group('S4: subnet scan debounce & transfer pause', () {
    test('a second scan inside minScanInterval is a no-op', () async {
      final sender = _CountingSender();
      final scanner = _scanner(sender);

      await scanner.scan(localIps: const []);
      final firstSweep = await _settledProbes(sender);
      expect(firstSweep, greaterThan(0),
          reason: 'first sweep must actually probe the well-known subnets');

      await scanner.scan(localIps: const []);
      expect(await _settledProbes(sender), firstSweep,
          reason: 're-kicks inside the debounce window must not probe again');
    });

    test('force bypasses the debounce window', () async {
      final sender = _CountingSender();
      final scanner = _scanner(sender);

      await scanner.scan(localIps: const []);
      final firstSweep = await _settledProbes(sender);

      await scanner.scan(localIps: const [], force: true);
      expect(await _settledProbes(sender), firstSweep * 2);
    });

    test('scan is skipped entirely while transfers are active', () async {
      final sender = _CountingSender();
      final scanner = _scanner(sender, minScanInterval: Duration.zero);

      scanner.transfersActive = true;
      await scanner.scan(localIps: const []);
      expect(sender.probes, 0);

      scanner.transfersActive = false;
      await scanner.scan(localIps: const []);
      expect(sender.probes, greaterThan(0));
    });

    test('scan resumes after the debounce window elapses', () async {
      final sender = _CountingSender();
      final scanner =
          _scanner(sender, minScanInterval: const Duration(milliseconds: 50));

      await scanner.scan(localIps: const []);
      final firstSweep = await _settledProbes(sender);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await scanner.scan(localIps: const []);
      expect(await _settledProbes(sender), firstSweep * 2);
    });
  });
}
