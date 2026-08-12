import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Best-effort free disk space for the volume containing [path], in bytes.
///
/// Returns null whenever the answer can't be determined — callers must
/// treat null as "unknown", never as "no space". A failed probe must never
/// block a transfer.
Future<int?> freeSpaceBytes(String path) async {
  try {
    if (Platform.isWindows) return _windowsFreeSpace(path);
    // POSIX (Linux, macOS, Android): `df -k` is universally available
    // (toybox on Android). Output: header line, then
    //   Filesystem 1K-blocks Used Available Use% Mounted on
    final result = await Process.run('df', ['-k', path]);
    if (result.exitCode != 0) return null;
    return parseDfAvailableBytes(result.stdout as String);
  } catch (_) {
    return null;
  }
}

/// Parses `df -k` output and returns the Available column in bytes, or null.
///
/// Robust to the two layouts real devices produce:
///  * normal: `/dev/sda1  62914560 10485760 52428800  17% /`
///  * wrapped: a long device name pushes the numbers onto their own line,
///    so the last line has no filesystem field and "Available" is no longer
///    the 4th column. (A naive `fields[3]` reads the `17%` token there and
///    silently disables the low-space warning — seen on Android where fuse
///    device names are long.)
///
/// Anchors on the use-percent token (`NN%`), which is unique in the row,
/// and takes the field just before it; this also survives mount points
/// containing spaces since those only appear after the percent column.
@visibleForTesting
int? parseDfAvailableBytes(String stdout) {
  final lines = stdout.trim().split('\n');
  if (lines.length < 2) return null;
  final fields = lines.last.trim().split(RegExp(r'\s+'));
  final pctIndex = fields.lastIndexWhere(
    (f) => RegExp(r'^\d{1,3}%$').hasMatch(f),
  );
  if (pctIndex < 1) return null;
  final availKb = int.tryParse(fields[pctIndex - 1]);
  if (availKb == null || availKb < 0) return null;
  return availKb * 1024;
}

int? _windowsFreeSpace(String path) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final getDiskFreeSpaceEx = kernel32.lookupFunction<
      Int32 Function(
          Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
      int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint64>)>('GetDiskFreeSpaceExW');
  final pathPtr = path.toNativeUtf16();
  final freeToCaller = calloc<Uint64>();
  final total = calloc<Uint64>();
  final totalFree = calloc<Uint64>();
  try {
    final ok = getDiskFreeSpaceEx(pathPtr, freeToCaller, total, totalFree);
    if (ok == 0) return null;
    return freeToCaller.value;
  } finally {
    calloc.free(pathPtr);
    calloc.free(freeToCaller);
    calloc.free(total);
    calloc.free(totalFree);
  }
}
