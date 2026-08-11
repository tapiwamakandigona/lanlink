import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/text_payload.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('text_payload_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('stages a snippet as a real .txt with matching metadata', () async {
    const text = 'wifi password: hunter2\nhttps://example.com';
    final info = await stageTextSnippet(text, tempDir);

    expect(info.fileType, 'text');
    expect(info.fileName, startsWith('Message '));
    expect(info.fileName, endsWith('.txt'));
    expect(info.localPath, isNotNull);

    final written = File(info.localPath!);
    expect(written.existsSync(), isTrue);
    expect(written.readAsStringSync(), text);
    expect(info.size, written.lengthSync());
  });

  test('unicode snippets round-trip byte-exact', () async {
    const text = 'héllo 🌍 — 中文';
    final info = await stageTextSnippet(text, tempDir);
    expect(File(info.localPath!).readAsStringSync(), text);
    // Size is byte length (UTF-8), not rune count.
    expect(info.size, greaterThan(text.length));
  });

  test('file name contains no path-hostile characters', () async {
    final info = await stageTextSnippet('x', tempDir);
    expect(info.fileName, isNot(matches(r'[<>:"/\\|?*]')));
  });
}
