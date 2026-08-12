import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/local_hotspot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lanlink/hotspot');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    LocalHotspot.debugForceSupported = true;
  });

  tearDown(() {
    LocalHotspot.debugForceSupported = false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('malformed native hotspot payload resolves null without throwing',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              'ssid': 7,
              'password': false,
              'hostIps': 'not-a-list',
            });

    await expectLater(LocalHotspot.start(), completion(isNull));
  });

  test('valid credentials retain only non-empty string host addresses',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              'ssid': 'LanLink',
              'password': 'secret',
              'hostIps': ['192.168.49.1', 4, '', null],
            });

    final info = await LocalHotspot.start();

    expect(info?.ssid, 'LanLink');
    expect(info?.hostIps, ['192.168.49.1']);
  });

  test('forced platform support also exercises permission bridge', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });

    expect(await LocalHotspot.hasPermission(), isTrue);
    expect(await LocalHotspot.requestPermission(), isTrue);
    expect(calls, ['hasPermission', 'requestPermission']);
  });
}
