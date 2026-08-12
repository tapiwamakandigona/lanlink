import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android activity teardown releases every long-lived platform owner',
      () {
    final source = File(
      'android/app/src/main/kotlin/com/lanlink/app/MainActivity.kt',
    ).readAsStringSync();
    final destroy = RegExp(
      r'override fun onDestroy\(\) \{([\s\S]*?)\n    \}',
    ).firstMatch(source);

    expect(destroy, isNotNull);
    final body = destroy!.group(1)!;
    expect(body, contains('leaveHotspotNetwork()'),
        reason: 'teardown must unbind the process and unregister the '
            'WifiNetworkSpecifier callback');
    expect(body, contains('hotspotPermissionResult?.let'),
        reason: 'a permission MethodChannel future must not hang when the '
            'Activity dies');
    expect(body, contains('pickFilesResult?.let'),
        reason: 'a document-picker MethodChannel future must not hang when '
            'the Activity dies');
    expect(body, contains('stopLocalHotspot()'));
    expect(body, contains('contentStreamExecutor.shutdownNow()'));
    expect(body, contains('thumbnailExecutor.shutdownNow()'));
  });
}
