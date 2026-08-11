import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/ui/v4/direct_connect/join_fallback_sheet.dart';

/// Regression tests for the Tier-3 password Copy button: on Android the
/// password must go through the native "lanlink/clipboard" copySensitive
/// op (which sets ClipDescription.EXTRA_IS_SENSITIVE on API 33+) instead
/// of the plain clipboard, with a graceful fallback when the native
/// handler is unavailable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const clipboardChannel = MethodChannel('lanlink/clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(clipboardChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: JoinFallbackSheet(
          ssid: 'LanLink-AB12',
          password: 'hunter2secret',
          canAddNetwork: false,
        ),
      ),
    ));
  }

  testWidgets('Android copy routes password through copySensitive',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    MethodCall? nativeCall;
    messenger.setMockMethodCallHandler(clipboardChannel, (call) async {
      nativeCall = call;
      return true;
    });
    var plainClipboardUsed = false;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') plainClipboardUsed = true;
      return null;
    });

    await pumpSheet(tester);
    await tester.tap(find.byTooltip('Copy password'));
    await tester.pump();

    expect(nativeCall?.method, 'copySensitive');
    expect(nativeCall?.arguments, {'text': 'hunter2secret'});
    expect(plainClipboardUsed, isFalse,
        reason: 'password must not hit the plain clipboard on Android');
    expect(find.text('Copied'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('falls back to plain clipboard when the native copy fails',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    messenger.setMockMethodCallHandler(clipboardChannel, (call) async {
      throw PlatformException(code: 'COPY_FAILED');
    });
    dynamic clipboardText;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'];
      }
      return null;
    });

    await pumpSheet(tester);
    await tester.tap(find.byTooltip('Copy password'));
    await tester.pump();

    expect(clipboardText, 'hunter2secret');
    expect(find.text('Copied'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('non-Android platforms use the plain clipboard directly',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    var nativeTouched = false;
    messenger.setMockMethodCallHandler(clipboardChannel, (call) async {
      nativeTouched = true;
      return true;
    });
    dynamic clipboardText;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'];
      }
      return null;
    });

    await pumpSheet(tester);
    await tester.tap(find.byTooltip('Copy password'));
    await tester.pump();

    expect(nativeTouched, isFalse);
    expect(clipboardText, 'hunter2secret');
    expect(find.text('Copied'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
