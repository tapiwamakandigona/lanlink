import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/free_space.dart';

void main() {
  test('reports positive free space for the temp volume', () async {
    final free = await freeSpaceBytes(Directory.systemTemp.path);
    expect(free, isNotNull);
    expect(free, greaterThan(0));
  });

  test('unknown path returns null instead of throwing', () async {
    final free = await freeSpaceBytes('/definitely/not/a/real/path/xyz');
    // df fails -> null (never an exception).
    expect(free, isNull);
  });

  _parserTests();
}

// --- parseDfAvailableBytes: pure-parser cases -------------------------------

const _normal = '''
Filesystem     1K-blocks     Used Available Use% Mounted on
/dev/sda1       62914560 10485760  52428800  17% /
''';

// Long device name wraps the numbers onto their own line (toybox/busybox df
// on Android does this). The old fields[3] read "17%" here and returned null.
const _wrapped = '''
Filesystem     1K-blocks     Used Available Use% Mounted on
/dev/block/very-long-device-mapper-name-that-wraps-the-row
                62914560 10485760  52428800  17% /storage/emulated
''';

const _spaceyMount = '''
Filesystem   1K-blocks     Used Available Use% Mounted on
/dev/disk1s1  62914560 10485760  52428800  17% /Volumes/My External Disk
''';

const _garbage = '''
Filesystem     1K-blocks     Used Available Use% Mounted on
/dev/sda1       what even is  this row  ??% /
''';

void _parserTests() {
  test('normal row parses Available column', () {
    expect(parseDfAvailableBytes(_normal), 52428800 * 1024);
  });

  test('wrapped row (long device name) still parses', () {
    expect(parseDfAvailableBytes(_wrapped), 52428800 * 1024);
  });

  test('mount point with spaces still parses', () {
    expect(parseDfAvailableBytes(_spaceyMount), 52428800 * 1024);
  });

  test('garbage degrades to null, never throws', () {
    expect(parseDfAvailableBytes(_garbage), isNull);
    expect(parseDfAvailableBytes(''), isNull);
    expect(parseDfAvailableBytes('just one line'), isNull);
  });
}
