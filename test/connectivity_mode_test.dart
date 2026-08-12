import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/connectivity/connectivity_mode.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy Bluetooth preference falls back to LAN when unsupported',
      () async {
    SharedPreferences.setMockInitialValues({
      'lanlink_connectivity_mode': 'bluetooth',
    });

    final settings = await AppSettings.load();

    expect(
      settings.connectivityMode,
      ConnectivityMode.lan,
      reason: 'an unavailable platform channel must never make every send fail',
    );
  });
}
