import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

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
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    // The data row can wrap when the device name is long; take the last
    // line and pick the 4th whitespace-separated column from the combined
    // tail fields.
    final fields = lines.last.trim().split(RegExp(r'\s+'));
    if (fields.length < 4) return null;
    final availKb = int.tryParse(fields[3]);
    if (availKb == null) return null;
    return availKb * 1024;
  } catch (_) {
    return null;
  }
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
