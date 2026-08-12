import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/incoming_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lanlink/incoming_share');

  setUp(() {
    IncomingShare.debugForceSupported = true;
  });

  tearDown(() {
    IncomingShare.debugForceSupported = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('stages an incoming content URI without copying it into app cache',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'consume');
      return [
        {
          'contentUri': 'content://photos/large-video',
          'fileName': 'large-video.mp4',
          'size': 8 * 1024 * 1024 * 1024,
        },
      ];
    });

    final files = await IncomingShare.consume();

    expect(files, hasLength(1));
    expect(files.single.fileName, 'large-video.mp4');
    expect(files.single.size, 8 * 1024 * 1024 * 1024);
    expect(files.single.contentUri, 'content://photos/large-video');
    expect(files.single.localPath, isNull);
  });

  test('malformed native rows are skipped without dropping valid shares',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      return [
        'not a map',
        {
          'contentUri': 'content://photos/bad-size',
          'fileName': 'bad.bin',
          'size': double.infinity,
        },
        {
          'contentUri': 'content://photos/good',
          'fileName': 'good.jpg',
          'size': 123,
        },
      ];
    });

    final files = await IncomingShare.consume();

    expect(files.map((file) => file.fileName), ['good.jpg']);
  });
}
