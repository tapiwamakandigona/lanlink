// Regression tests for B1: a lost platform reply to `join` must not wedge
// the caller forever — the Dart side guards the call with its own timeout
// resolving to [WifiJoinResult.timeout].

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/wifi_joiner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lanlink/wifi');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    WifiJoiner.debugPlatformSupportedOverride = true;
  });

  tearDown(() {
    WifiJoiner.debugPlatformSupportedOverride = null;
    WifiJoiner.joinReplyTimeout = const Duration(seconds: 90);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('join resolves to timeout when the platform reply never arrives',
      () async {
    WifiJoiner.joinReplyTimeout = const Duration(milliseconds: 200);
    messenger.setMockMethodCallHandler(channel, (call) {
      expect(call.method, 'join');
      // Simulate a lost reply: the platform side never answers.
      return Completer<Object?>().future;
    });

    final result = await WifiJoiner.join('ssid', 'password')
        .timeout(const Duration(seconds: 5));
    expect(result, WifiJoinResult.timeout);
  });

  test('join still maps a prompt platform reply normally', () async {
    WifiJoiner.joinReplyTimeout = const Duration(milliseconds: 200);
    messenger.setMockMethodCallHandler(channel, (call) async => 'connected');

    final result = await WifiJoiner.join('ssid', 'password');
    expect(result, WifiJoinResult.connected);
    expect(result.joined, isTrue);
  });

  test('a platform-side error still maps to error, not timeout', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });

    final result = await WifiJoiner.join('ssid', 'password');
    expect(result, WifiJoinResult.error);
  });
}
