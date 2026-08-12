import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/android_apps.dart';
import 'package:lanlink/core/platform/media_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const appsChannel = MethodChannel('lanlink/android_apps');
  const mediaChannel = MethodChannel('lanlink/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    AndroidApps.debugForceSupported = true;
    MediaLibrary.debugForceSupported = true;
  });

  tearDown(() {
    AndroidApps.debugForceSupported = false;
    MediaLibrary.debugForceSupported = false;
    messenger.setMockMethodCallHandler(appsChannel, null);
    messenger.setMockMethodCallHandler(mediaChannel, null);
  });

  test('app listing skips malformed rows and keeps valid apps', () async {
    messenger.setMockMethodCallHandler(
        appsChannel,
        (_) async => [
              'bad',
              {
                'label': 'Broken',
                'packageName': 'com.bad',
                'apkPath': '/bad.apk',
                'size': double.infinity,
              },
              {
                'label': 'Good',
                'packageName': 'com.good',
                'apkPath': '/good.apk',
                'size': 123,
              },
            ]);

    final apps = await AndroidApps.listLaunchableApps();

    expect(apps.map((app) => app.packageName), ['com.good']);
  });

  test('media listing skips malformed rows and keeps valid media', () async {
    messenger.setMockMethodCallHandler(
        mediaChannel,
        (_) async => [
              null,
              {
                'id': double.nan,
                'name': 'bad.jpg',
                'path': '',
                'size': 1,
                'isVideo': false,
              },
              {
                'id': 7,
                'name': 'good.jpg',
                'path': '',
                'contentUri': 'content://media/7',
                'size': 456,
                'isVideo': false,
                'dateModified': 100,
                'bucket': 'Camera',
              },
            ]);

    final media = await MediaLibrary.listMedia();

    expect(media.map((item) => item.name), ['good.jpg']);
  });
}
