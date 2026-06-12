import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/theme/app_theme.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/simple/connect/send_connect_page.dart';
import 'package:lanlink/ui/simple/simple_home_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'lanlink_alias': 'Test phone',
      'lanlink_simple_mode_v1': true,
      'lanlink_connectivity_default_applied_v1': true,
    });
  });

  testWidgets('Simple mode offers Connect to a computer and opens the page',
      (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      state = AppState.forScreenshots(settings: await AppSettings.load());
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: state.settings),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SimpleHomePage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final button = find.text('Connect to a computer');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SendConnectPage), findsOneWidget);
  });
}
