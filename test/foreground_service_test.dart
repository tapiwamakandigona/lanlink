import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/foreground_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lanlink/foreground_service');
  final service = TransferForegroundService.instance;

  setUp(() async {
    TransferForegroundService.debugForceSupported = true;
    await service.debugReset();
  });

  tearDown(() async {
    await service.debugReset();
    TransferForegroundService.debugForceSupported = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a stop cannot overtake a slow foreground-service start', () async {
    final allowStartToFinish = Completer<void>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') {
        calls.add('start began');
        await allowStartToFinish.future;
        calls.add('start finished');
      } else {
        calls.add(call.method);
      }
      return true;
    });

    final start = service.sync(1);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start began']);

    final stop = service.sync(0);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start began'],
        reason: 'stop must wait until the native start call has settled');

    allowStartToFinish.complete();
    await Future.wait([start, stop]);
    expect(calls, ['start began', 'start finished', 'stop']);
  });

  test('a start cannot overtake a slow foreground-service stop', () async {
    final allowStopToFinish = Completer<void>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'stop') {
        calls.add('stop began');
        await allowStopToFinish.future;
        calls.add('stop finished');
      } else {
        calls.add(call.method);
      }
      return true;
    });

    await service.sync(1);
    final stop = service.sync(0);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start', 'stop began']);

    final restart = service.sync(2);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start', 'stop began'],
        reason: 'restart must wait until the native stop call has settled');

    allowStopToFinish.complete();
    await Future.wait([stop, restart]);
    expect(calls, ['start', 'stop began', 'stop finished', 'start']);
  });

  test('rapid pending counts coalesce to the newest summary', () async {
    final allowFirstStart = Completer<void>();
    final counts = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') {
        counts.add((call.arguments as Map)['activeCount'] as int);
        if (counts.length == 1) await allowFirstStart.future;
      }
      return true;
    });

    final first = service.sync(1);
    await Future<void>.delayed(Duration.zero);
    final second = service.sync(2);
    final third = service.sync(3);
    allowFirstStart.complete();
    await Future.wait([first, second, third]);

    expect(counts, [1, 3]);
  });

  test('platform exceptions do not strand the transition queue', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (calls.length == 1) {
        throw PlatformException(code: 'denied');
      }
      return true;
    });

    await service.sync(1);
    await service.sync(0);
    expect(calls, ['start', 'stop']);
  });

  test('rapid start then stop in one turn never loses the stop', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });

    final start = service.sync(1);
    final stop = service.sync(0);
    await Future.wait([start, stop]);

    expect(calls.last, 'stop');
  });
}
