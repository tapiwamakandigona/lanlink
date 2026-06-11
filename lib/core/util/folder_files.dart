import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/file_info.dart';

const _uuid = Uuid();

/// Walks [folderPath] recursively and returns one [FileInfo] per regular
/// file, with `fileName` carrying the path relative to the folder's parent
/// using `/` separators — e.g. picking `/sdcard/DCIM/Holiday` produces
/// `Holiday/IMG_001.jpg`, `Holiday/clips/video.mp4`, …
///
/// Symlinks are not followed (no cycles, no surprise escapes) and the
/// result is sorted by relative path so transfers are deterministic.
Future<List<FileInfo>> fileInfosForFolder(String folderPath) async {
  final dir = Directory(folderPath);
  if (!await dir.exists()) return const [];
  final folderName = p.basename(p.normalize(folderPath));

  final out = <FileInfo>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: dir.path);
    final wireName = [folderName, ...p.split(rel)].join('/');
    out.add(FileInfo(
      id: _uuid.v4(),
      fileName: wireName,
      size: await entity.length(),
      fileType: fileTypeForName(p.basename(entity.path)),
      localPath: entity.path,
    ));
  }
  out.sort((a, b) => a.fileName.compareTo(b.fileName));
  return out;
}
