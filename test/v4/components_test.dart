// Behavior tests for the v4 "Ember on Paper" component library.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/ui/v4/gallery.dart';
import 'package:lanlink/ui/v4/v4.dart';

Widget _host(Widget child, {bool dark = false, double width = 390}) {
  return MaterialApp(
    theme: dark ? EmberTheme.dark() : EmberTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

void main() {
  // ─── Theme & tokens ─────────────────────────────────────────────────
  group('EmberTheme', () {
    test('registers EmberSemantics in both themes', () {
      expect(EmberTheme.light().extension<EmberSemantics>(),
          same(EmberSemantics.light));
      expect(EmberTheme.dark().extension<EmberSemantics>(),
          same(EmberSemantics.dark));
    });

    test('semantic colors are distinct from each other and from primary', () {
      for (final (semantics, scheme) in [
        (EmberSemantics.light, EmberTheme.light().colorScheme),
        (EmberSemantics.dark, EmberTheme.dark().colorScheme),
      ]) {
        expect(semantics.success, isNot(equals(semantics.warning)));
        expect(semantics.success, isNot(equals(semantics.danger)));
        expect(semantics.success, isNot(equals(scheme.primary)));
      }
    });

    test('single-green rule: no component file hard-codes a Color literal', () {
      // The one structural guarantee of v4: colors live only in
      // lib/ui/v4/theme/. Any Color(0x...) literal elsewhere is a bug.
      final dir = Directory('lib/ui/v4');
      expect(dir.existsSync(), isTrue,
          reason: 'run tests from the package root');
      final offenders = <String>[];
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.path.contains(
            '${Platform.pathSeparator}theme${Platform.pathSeparator}')) {
          continue;
        }
        if (f.readAsStringSync().contains('Color(0x')) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: 'hard-coded Color literals outside lib/ui/v4/theme/');
    });
  });

  // ─── Two-verb home ──────────────────────────────────────────────────
  group('TwoVerbHome', () {
    testWidgets('fires onSend and onReceive', (tester) async {
      var sent = 0, received = 0;
      await tester.pumpWidget(_host(TwoVerbHome(
        deviceName: 'Marmalade-Fox',
        onSend: () => sent++,
        onReceive: () => received++,
      )));
      await tester.tap(find.text('Send'));
      await tester.tap(find.text('Receive'));
      expect(sent, 1);
      expect(received, 1);
    });

    testWidgets('shows visibility line with the device name', (tester) async {
      await tester.pumpWidget(_host(TwoVerbHome(
        deviceName: 'Marmalade-Fox',
        onSend: () {},
        onReceive: () {},
      )));
      expect(
        find.textContaining('Marmalade-Fox', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('hidden state drops the name and says hidden', (tester) async {
      await tester.pumpWidget(_host(TwoVerbHome(
        deviceName: 'Marmalade-Fox',
        visible: false,
        onSend: () {},
        onReceive: () {},
      )));
      expect(
        find.textContaining("You're hidden", findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Marmalade-Fox', findRichText: true),
        findsNothing,
      );
    });

    testWidgets(
        'hidden + onRetryVisibility: shows "tap to retry" and fires the '
        'callback on tap', (tester) async {
      var retried = 0;
      await tester.pumpWidget(_host(TwoVerbHome(
        deviceName: 'Marmalade-Fox',
        visible: false,
        onRetryVisibility: () => retried++,
        onSend: () {},
        onReceive: () {},
      )));
      expect(
        find.textContaining('tap to retry', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byType(VisibilityStatusLine));
      expect(retried, 1);
    });

    testWidgets('hidden without retry callback stays non-interactive',
        (tester) async {
      await tester.pumpWidget(_host(TwoVerbHome(
        deviceName: 'Marmalade-Fox',
        visible: false,
        onSend: () {},
        onReceive: () {},
      )));
      expect(
        find.textContaining('tap to retry', findRichText: true),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(VisibilityStatusLine),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('verb cards and retry line expose button semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(TwoVerbHome(
        deviceName: 'Marmalade-Fox',
        visible: false,
        onRetryVisibility: () {},
        onSend: () {},
        onReceive: () {},
      )));
      expect(
        find.bySemanticsLabel(RegExp('Send. Pick files')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Receive. Show a code')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Retry becoming visible')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('renders the inline session strip slot', (tester) async {
      const marker = Key('strip');
      await tester.pumpWidget(_host(TwoVerbHome(
        deviceName: 'Marmalade-Fox',
        onSend: () {},
        onReceive: () {},
        sessionStrip: const SizedBox(key: marker, height: 40),
      )));
      expect(find.byKey(marker), findsOneWidget);
    });

    testWidgets('lays out without overflow at 390 and 1200 wide',
        (tester) async {
      for (final width in [390.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(
          TwoVerbHome(
              deviceName: 'Marmalade-Fox', onSend: () {}, onReceive: () {}),
          width: width,
        ));
        expect(tester.takeException(), isNull, reason: 'width $width');
      }
    });

    testWidgets('verb cards grow at 2x accessibility text scale (no clip)',
        (tester) async {
      // Regression: fixed 180/300px card heights overflowed as soon as the
      // user ran a large system font. Heights now scale with the text scaler.
      for (final width in [390.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(_host(
          TwoVerbHome(
              deviceName: 'Marmalade-Fox', onSend: () {}, onReceive: () {}),
          width: width,
        ));
        expect(tester.takeException(), isNull, reason: 'width $width @2x');
      }
    });
  });

  // ─── Device radar ───────────────────────────────────────────────────
  group('DeviceRadar', () {
    const peers = [
      RadarPeerData(
          id: 'fp-otter',
          name: 'Purple-Otter',
          deviceType: DeviceType.laptop,
          verified: true),
      RadarPeerData(
          id: 'fp-heron', name: 'Sunny-Heron', deviceType: DeviceType.phone),
    ];

    testWidgets('shows names, never addresses', (tester) async {
      await tester
          .pumpWidget(_host(DeviceRadar(peers: peers, onPeerTap: (_) {})));
      expect(find.text('Purple-Otter'), findsOneWidget);
      expect(find.text('Sunny-Heron'), findsOneWidget);
      // No IP:port-looking text anywhere on the radar.
      expect(
        find.textContaining(RegExp(r'\d+\.\d+\.\d+\.\d+')),
        findsNothing,
      );
      expect(find.textContaining(':53317'), findsNothing);
    });

    testWidgets('tap reports the tapped peer', (tester) async {
      RadarPeerData? tapped;
      await tester.pumpWidget(
          _host(DeviceRadar(peers: peers, onPeerTap: (p) => tapped = p)));
      await tester.tap(find.text('Sunny-Heron'));
      expect(tapped, peers[1]);
    });

    testWidgets('verified peers get a badge, unverified do not',
        (tester) async {
      await tester
          .pumpWidget(_host(DeviceRadar(peers: peers, onPeerTap: (_) {})));
      // Only Purple-Otter is verified -> exactly one compact badge.
      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('empty + searching shows the looking-around state',
        (tester) async {
      await tester
          .pumpWidget(_host(DeviceRadar(peers: const [], onPeerTap: (_) {})));
      await tester.pump();
      expect(find.text('Looking around…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('empty + not searching shows the no-devices state',
        (tester) async {
      await tester.pumpWidget(_host(
          DeviceRadar(peers: const [], searching: false, onPeerTap: (_) {})));
      expect(find.text('No devices found yet'), findsOneWidget);
      // The empty state must coach, not dead-end: same Wi-Fi + QR escape.
      expect(find.textContaining('same Wi-Fi'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    test('initialsFor handles hyphenated, single, and empty names', () {
      expect(DeviceBubble.initialsFor('Purple-Otter'), 'PO');
      expect(DeviceBubble.initialsFor('Sunny Heron'), 'SH');
      expect(DeviceBubble.initialsFor('Otter'), 'OT');
      expect(DeviceBubble.initialsFor('X'), 'X');
      expect(DeviceBubble.initialsFor(''), '?');
    });
  });

  // ─── Session card ───────────────────────────────────────────────────
  group('SessionCard', () {
    const transferring = SessionCardData(
      title: 'holiday-video.mp4',
      totalSize: '1.2 GB',
      peerName: 'Purple-Otter',
      status: SessionStatus.transferring,
      progress: 0.38,
      speed: '41 MB/s',
      eta: 'about 2 min left',
    );

    testWidgets('active: shows progress, speed, ETA, percent and Stop',
        (tester) async {
      var stopped = 0;
      await tester.pumpWidget(
          _host(SessionCard(data: transferring, onStop: () => stopped++)));
      expect(find.text('41 MB/s'), findsOneWidget);
      expect(find.text('about 2 min left'), findsOneWidget);
      expect(find.text('38%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      await tester.tap(find.text('Stop'));
      expect(stopped, 1);
    });

    testWidgets('waiting: indeterminate bar + waiting copy', (tester) async {
      await tester.pumpWidget(_host(SessionCard(
        data: const SessionCardData(
          title: 'holiday-video.mp4',
          totalSize: '1.2 GB',
          status: SessionStatus.waiting,
        ),
        onStop: () {},
      )));
      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, isNull);
      expect(find.text('Waiting for them to accept…'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
    });

    testWidgets('sent: Sent! chip, Dismiss fires, no progress bar',
        (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(_host(SessionCard(
        data: const SessionCardData(
          title: '14 photos',
          fileCount: 14,
          totalSize: '48 MB',
          peerName: 'Purple-Otter',
          status: SessionStatus.sent,
        ),
        onDismiss: () => dismissed++,
      )));
      expect(find.text('Sent!'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('14 files · 48 MB · to Purple-Otter'), findsOneWidget);
      await tester.tap(find.text('Dismiss'));
      expect(dismissed, 1);
    });

    testWidgets('failed: hint shown, Try again and Dismiss fire',
        (tester) async {
      var retried = 0, dismissed = 0;
      await tester.pumpWidget(_host(SessionCard(
        data: const SessionCardData(
          title: 'project-archive.zip',
          totalSize: '620 MB',
          status: SessionStatus.failed,
          errorHint: 'The connection was lost.',
        ),
        onRetry: () => retried++,
        onDismiss: () => dismissed++,
      )));
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('The connection was lost.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.tap(find.text('Dismiss'));
      expect(retried, 1);
      expect(dismissed, 1);
    });

    testWidgets('cancelled: neutral terminal state with Dismiss only',
        (tester) async {
      await tester.pumpWidget(_host(SessionCard(
        data: const SessionCardData(
          title: 'soundtrack.flac',
          totalSize: '86 MB',
          status: SessionStatus.cancelled,
        ),
        onDismiss: () {},
      )));
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('terminal chips use the semantic palette (single green)',
        (tester) async {
      await tester.pumpWidget(_host(const Column(children: [
        SessionStatusChip(status: SessionStatus.sent),
        SessionStatusChip(status: SessionStatus.failed),
      ])));
      final context = tester.element(find.byType(Column).first);
      final ember = context.ember;
      Text chipText(String label) => tester.widget<Text>(find.text(label));
      expect(chipText('Sent!').style?.color, ember.onSuccessContainer);
      expect(chipText('Failed').style?.color, ember.onDangerContainer);
    });
  });

  // ─── Consent sheet ──────────────────────────────────────────────────
  group('ConsentSheet', () {
    const request = ConsentRequestData(
      senderName: 'Purple-Otter',
      fileCount: 14,
      totalSize: '48 MB',
      verified: true,
      previewFileNames: ['IMG_2041.jpg', 'IMG_2042.jpg', 'IMG_2043.jpg'],
    );

    testWidgets('states who wants to send what, with Verified badge',
        (tester) async {
      await tester.pumpWidget(_host(
          ConsentSheet(data: request, onAccept: () {}, onDecline: () {})));
      expect(find.text('Purple-Otter'), findsOneWidget);
      expect(find.text('wants to send you 14 files (48 MB)'), findsOneWidget);
      expect(find.byType(VerifiedBadge), findsOneWidget);
      expect(find.text('IMG_2041.jpg'), findsOneWidget);
      expect(find.text('and 11 more'), findsOneWidget);
      // Calm and hash-free: no fingerprint-looking text.
      expect(find.textContaining(RegExp(r'[0-9a-f]{8,}')), findsNothing);
    });

    testWidgets('singular wording and no badge when unverified',
        (tester) async {
      await tester.pumpWidget(_host(ConsentSheet(
        data: const ConsentRequestData(
            senderName: 'Sunny-Heron', fileCount: 1, totalSize: '1.2 GB'),
        onAccept: () {},
        onDecline: () {},
      )));
      expect(find.text('wants to send you 1 file (1.2 GB)'), findsOneWidget);
      expect(find.byType(VerifiedBadge), findsNothing);
    });

    testWidgets('warning line renders when provided', (tester) async {
      await tester.pumpWidget(_host(ConsentSheet(
        data: const ConsentRequestData(
          senderName: 'Sunny-Heron',
          fileCount: 1,
          totalSize: '1.2 GB',
          warning: 'Low on space: only 800 MB free where files are saved.',
        ),
        onAccept: () {},
        onDecline: () {},
      )));
      await tester.pump(); // let the warning FutureBuilder resolve
      expect(find.textContaining('Low on space'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      // Still a warning, not a block.
      expect(find.text('Accept'), findsOneWidget);
    });

    testWidgets('Accept and Decline fire their callbacks', (tester) async {
      var accepted = 0, declined = 0;
      await tester.pumpWidget(_host(ConsentSheet(
        data: request,
        onAccept: () => accepted++,
        onDecline: () => declined++,
      )));
      await tester.tap(find.text('Accept'));
      await tester.tap(find.text('Decline'));
      expect(accepted, 1);
      expect(declined, 1);
    });
  });

  // ─── QR panels ──────────────────────────────────────────────────────
  group('QR panels', () {
    testWidgets('QrDisplayPanel shows name + caption around the code',
        (tester) async {
      await tester.pumpWidget(_host(const QrDisplayPanel(
        payload: 'lanlink://connect/abc',
        deviceName: 'Marmalade-Fox',
      )));
      expect(find.text('Marmalade-Fox'), findsOneWidget);
      expect(find.text('Scan this from the sending device'), findsOneWidget);
    });

    testWidgets('QrScanFrame shows hint and hosts an injected preview',
        (tester) async {
      const preview = Key('camera-preview');
      await tester.pumpWidget(_host(const QrScanFrame(
        child: SizedBox(key: preview),
      )));
      expect(find.byKey(preview), findsOneWidget);
      expect(find.textContaining('Point at the code'), findsOneWidget);
    });
  });

  // ─── Gallery smoke ──────────────────────────────────────────────────
  testWidgets('gallery builds in light and dark without exceptions',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(V4GalleryApp(themeMode: mode));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$mode');
    }
  });
}
