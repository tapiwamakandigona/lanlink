// Unit tests for the `lanlink/saf` Dart bridge: chunked reads over the
// method channel, EOF handling, offset forwarding, and guaranteed handle
// close — including when the consumer cancels mid-stream.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/content_streams.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lanlink/saf');

  final calls = <MethodCall>[];
  List<Uint8List?> chunkQueue = [];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'openStream':
          return 7;
        case 'readChunk':
          return chunkQueue.isEmpty ? null : chunkQueue.removeAt(0);
        case 'closeStream':
          return null;
        case 'pickFiles':
          return [
            {'uri': 'content://x/1', 'name': 'a.mp4', 'size': 1234},
          ];
      }
      return null;
    });
  }

  setUp(() {
    calls.clear();
    chunkQueue = [];
    install();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('pickFiles maps native maps to PickedContent', () async {
    final picked = await ContentStreams.pickFiles();
    expect(picked, hasLength(1));
    expect(picked.single.uri, 'content://x/1');
    expect(picked.single.name, 'a.mp4');
    expect(picked.single.size, 1234);
  });

  test('openRead yields chunks until EOF and closes the handle', () async {
    chunkQueue = [
      Uint8List.fromList([1, 2, 3]),
      Uint8List.fromList([4, 5]),
    ];
    final got = <int>[];
    await for (final chunk in ContentStreams.openRead('content://x/1')) {
      got.addAll(chunk);
    }
    expect(got, [1, 2, 3, 4, 5]);

    final open = calls.singleWhere((c) => c.method == 'openStream');
    expect(open.arguments, {'uri': 'content://x/1', 'offset': 0});
    // 2 data chunks + 1 EOF probe.
    expect(calls.where((c) => c.method == 'readChunk'), hasLength(3));
    // Handle must be closed exactly once. The close is fire-and-forget,
    // so give the microtask queue a beat.
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'closeStream'), hasLength(1));
    expect(calls.last.arguments, {'id': 7});
  });

  test('openRead forwards the resume offset', () async {
    chunkQueue = [];
    await ContentStreams.openRead('content://x/1', start: 4096).drain<void>();
    final open = calls.singleWhere((c) => c.method == 'openStream');
    expect(open.arguments, {'uri': 'content://x/1', 'offset': 4096});
  });

  test('cancelling mid-stream still closes the handle', () async {
    chunkQueue = [
      Uint8List.fromList([1]),
      Uint8List.fromList([2]),
      Uint8List.fromList([3]),
    ];
    // Take only the first chunk, then cancel.
    await ContentStreams.openRead('content://x/1').first;
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'closeStream'), hasLength(1));
  });
}
