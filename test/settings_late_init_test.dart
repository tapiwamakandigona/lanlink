// Regression test for the settings-path LateInitializationError: AppState
// used `late` fields for its network services, so any AppState instance
// whose services had not been started (screenshot/test instances, or reads
// racing bootstrap) crashed with LateInitializationError as soon as the
// Settings page read `state.port` — and again in `dispose()`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:lanlink/ui/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'SettingsPage renders on a state whose services never started '
      '(no LateInitializationError)', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pump();

    // The page rendered instead of crashing on `state.port`.
    expect(tester.takeException(), isNull);
    expect(find.text('Settings'), findsOneWidget);
  });

  test('port is null and dispose() is safe before services start', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState.forScreenshots(settings: await AppSettings.load());
    expect(state.port, isNull);
    expect(state.dispose, returnsNormally);
  });
}
