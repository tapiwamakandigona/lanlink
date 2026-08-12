import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/local_hotspot.dart';
import 'package:lanlink/ui/v4/direct_connect/hotspot_host_controller.dart';

const _info = HotspotInfo(
  ssid: 'AndroidShare_1234',
  password: 'p4ssw0rd',
  hostIps: ['192.168.49.1'],
);

/// Builds a controller with faked platform calls; every call is recorded.
HotspotHostController _controller({
  required List<String> log,
  bool supported = true,
  bool permitted = true,
  bool grantOutcome = true,
  HotspotInfo? startResult = _info,
}) =>
    HotspotHostController(
      isSupported: () async {
        log.add('isSupported');
        return supported;
      },
      hasPermission: () async {
        log.add('hasPermission');
        return permitted;
      },
      requestPermission: () async {
        log.add('requestPermission');
        return grantOutcome;
      },
      start: () async {
        log.add('start');
        return startResult;
      },
      stop: () async {
        log.add('stop');
      },
    );

void main() {
  group('HotspotHostController', () {
    test('enable: supported + permitted goes straight to running', () async {
      final log = <String>[];
      final c = _controller(log: log);
      await c.enable();
      expect(c.phase, HotspotHostPhase.running);
      expect(c.isRunning, isTrue);
      expect(c.info?.ssid, 'AndroidShare_1234');
      expect(log, ['isSupported', 'hasPermission', 'start']);
    });

    test('enable: unsupported platform fails without touching start', () async {
      final log = <String>[];
      final c = _controller(log: log, supported: false);
      await c.enable();
      expect(c.phase, HotspotHostPhase.failed);
      expect(c.error, contains('Android 8'));
      expect(log, isNot(contains('start')));
    });

    test(
        'enable: missing permission pauses at needsPermission; grant '
        'continues to running', () async {
      final log = <String>[];
      final c = _controller(log: log, permitted: false);
      await c.enable();
      expect(c.phase, HotspotHostPhase.needsPermission);
      expect(log, isNot(contains('start')));

      await c.grantPermission();
      expect(c.phase, HotspotHostPhase.running);
      expect(log, contains('requestPermission'));
      expect(log.last, 'start');
    });

    test('grant declined fails with a friendly message', () async {
      final log = <String>[];
      final c = _controller(log: log, permitted: false, grantOutcome: false);
      await c.enable();
      await c.grantPermission();
      expect(c.phase, HotspotHostPhase.failed);
      expect(c.error, contains('declined'));
      expect(log, isNot(contains('start')));
    });

    test('platform refusing to start (null info) fails with guidance',
        () async {
      final log = <String>[];
      final c = _controller(log: log, startResult: null);
      await c.enable();
      expect(c.phase, HotspotHostPhase.failed);
      expect(c.error, contains('Location'));
    });

    test('disable from running stops the platform hotspot and clears info',
        () async {
      final log = <String>[];
      final c = _controller(log: log);
      await c.enable();
      await c.disable();
      expect(c.phase, HotspotHostPhase.idle);
      expect(c.info, isNull);
      expect(log.last, 'stop');
    });

    test('disable while idle never calls stop', () async {
      final log = <String>[];
      final c = _controller(log: log);
      await c.disable();
      expect(log, isNot(contains('stop')));
    });

    test('dispose with a live hotspot tears the reservation down', () async {
      final log = <String>[];
      final c = _controller(log: log);
      await c.enable();
      c.dispose();
      expect(log.last, 'stop');
    });

    test('disable while start is pending cannot resurrect an orphan hotspot',
        () async {
      final startEntered = Completer<void>();
      final startResult = Completer<HotspotInfo?>();
      var stops = 0;
      final c = HotspotHostController(
        isSupported: () async => true,
        hasPermission: () async => true,
        requestPermission: () async => true,
        start: () {
          startEntered.complete();
          return startResult.future;
        },
        stop: () async => stops++,
      );

      final enabling = c.enable();
      await startEntered.future;
      expect(c.phase, HotspotHostPhase.starting);

      await c.disable();
      startResult.complete(_info);
      await enabling;

      expect(c.phase, HotspotHostPhase.idle);
      expect(c.info, isNull);
      expect(
        stops,
        2,
        reason: 'stop once on disable and again when the late reservation '
            'materialises',
      );
    });

    test('platform start exception becomes a failed state, not a stuck future',
        () async {
      final c = HotspotHostController(
        isSupported: () async => true,
        hasPermission: () async => true,
        requestPermission: () async => true,
        start: () => Future<HotspotInfo?>.error(StateError('native died')),
        stop: () async {},
      );

      await expectLater(c.enable(), completes);

      expect(c.phase, HotspotHostPhase.failed);
      expect(c.error, isNotEmpty);
    });

    group('on Windows', () {
      setUp(() {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      });
      tearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });

      test('enable skips the permission check entirely', () async {
        // Even a hasPermission fake that would say "no" must never be
        // consulted: Windows has no runtime permission to grant.
        final log = <String>[];
        final c = _controller(log: log, permitted: false);
        await c.enable();
        expect(c.phase, HotspotHostPhase.running);
        expect(log, ['isSupported', 'start']);
      });

      test('unsupported message talks about the PC, not Android', () async {
        final log = <String>[];
        final c = _controller(log: log, supported: false);
        await c.enable();
        expect(c.phase, HotspotHostPhase.failed);
        expect(c.error, contains('Wi-Fi adapter'));
        expect(c.error, isNot(contains('Android')));
      });

      test('start refusal message is Windows-flavoured', () async {
        final log = <String>[];
        final c = _controller(log: log, startResult: null);
        await c.enable();
        expect(c.phase, HotspotHostPhase.failed);
        expect(c.error, contains('Wi-Fi'));
        expect(c.error, isNot(contains('Location')));
      });
    });

    test('notifies listeners on every phase change', () async {
      final log = <String>[];
      final c = _controller(log: log);
      final phases = <HotspotHostPhase>[];
      c.addListener(() => phases.add(c.phase));
      await c.enable();
      await c.disable();
      expect(
        phases,
        [
          HotspotHostPhase.checking,
          HotspotHostPhase.starting,
          HotspotHostPhase.running,
          HotspotHostPhase.idle,
        ],
      );
    });
  });
}
