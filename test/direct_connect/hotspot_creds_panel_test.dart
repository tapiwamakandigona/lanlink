// Widget tests for the host-side manual-join credentials panel.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/ui/v4/direct_connect/hotspot_creds_panel.dart';
import 'package:lanlink/ui/v4/v4.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget host(Widget child) => MaterialApp(
        theme: EmberTheme.light(),
        home: Scaffold(body: child),
      );

  testWidgets('shows the SSID and password', (tester) async {
    await tester.pumpWidget(host(const HotspotCredsPanel(
      ssid: 'DIRECT-xy-LanLink',
      password: 'p4ssw0rd',
    )));
    expect(find.text('DIRECT-xy-LanLink'), findsOneWidget);
    expect(find.text('p4ssw0rd'), findsOneWidget);
  });

  testWidgets(
      'copy button puts the password on the clipboard and shows an '
      'inline Copied state that resets', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });

    await tester.pumpWidget(host(const HotspotCredsPanel(
      ssid: 'DIRECT-xy-LanLink',
      password: 'p4ssw0rd',
    )));

    await tester.tap(find.byTooltip('Copy password'));
    await tester.pump();

    expect(copied, 'p4ssw0rd');
    // Feedback is inline (a SnackBar could render behind the hosting
    // surface), and the copy button is temporarily swapped out.
    expect(find.text('Copied'), findsOneWidget);
    expect(find.byTooltip('Copy password'), findsNothing);

    // After the reset timer the affordance returns for another copy.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
    expect(find.byTooltip('Copy password'), findsOneWidget);
  });
}
