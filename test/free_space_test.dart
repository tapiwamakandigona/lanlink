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
}
