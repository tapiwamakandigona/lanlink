import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/app_invite.dart';
import 'package:lanlink/ui/widgets/invite_friend_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lanlink/app_invite');

  tearDown(() {
    AppInvite.debugIsSupportedOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  testWidgets('renders nothing on unsupported platforms', (tester) async {
    AppInvite.debugIsSupportedOverride = false;
    await tester.pumpWidget(host(const InviteFriendTile(version: '4.1.0')));

    expect(find.text('Invite a friend'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('shows the tile with the install-unknown-apps hint on Android',
      (tester) async {
    AppInvite.debugIsSupportedOverride = true;
    await tester.pumpWidget(host(const InviteFriendTile(version: '4.1.0')));

    expect(find.text('Invite a friend'), findsOneWidget);
    expect(
      find.textContaining('install unknown apps'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the tile asks the platform to share the APK',
      (tester) async {
    AppInvite.debugIsSupportedOverride = true;
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return 'shared';
    });

    await tester.pumpWidget(host(const InviteFriendTile(version: '4.1.0')));
    await tester.tap(find.text('Invite a friend'));
    await tester.pumpAndSettle();

    expect(received?.method, 'shareApk');
    expect(received?.arguments, {'fileName': 'LanLink-v4.1.0.apk'});
    // Nothing else pops up — the OS share sheet takes over.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('split installs fall back to the download-link dialog',
      (tester) async {
    AppInvite.debugIsSupportedOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'split');

    await tester.pumpWidget(host(const InviteFriendTile(version: '4.1.0')));
    await tester.tap(find.text('Invite a friend'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(AppInvite.downloadUrl), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);
  });

  testWidgets('failure shows a quiet snackbar', (tester) async {
    AppInvite.debugIsSupportedOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'share_failed');
    });

    await tester.pumpWidget(host(const InviteFriendTile(version: '4.1.0')));
    await tester.tap(find.text('Invite a friend'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('Couldn\'t share the app right now.'),
      findsOneWidget,
    );
  });
}
