import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/file_info.dart';
import 'folder_files.dart';

const _uuid = Uuid();

/// Turns raw filesystem paths (from a desktop drag-and-drop) into staged
/// [FileInfo]s.
///
/// - Regular files become one [FileInfo] each.
/// - Directories are walked recursively via [fileInfosForFolder], so a
///   dropped folder keeps its structure on the receiving side exactly like
///   a folder picked through the picker.
/// - Paths that no longer exist (or are neither file nor directory) are
///   silently skipped — a drop must never throw.
Future<List<FileInfo>> fileInfosForDroppedPaths(List<String> paths) async {
  final out = <FileInfo>[];
  for (final path in paths) {
    try {
      final type = await FileSystemEntity.type(path, followLinks: true);
      if (type == FileSystemEntityType.file) {
        final f = File(path);
        out.add(FileInfo(
          id: _uuid.v4(),
          fileName: p.basename(path),
          size: await f.length(),
          fileType: fileTypeForName(p.basename(path)),
          localPath: path,
        ));
      } else if (type == FileSystemEntityType.directory) {
        out.addAll(await fileInfosForFolder(path));
      }
    } catch (_) {
      // Unreadable entry — skip it rather than abort the whole drop.
    }
  }
  return out;
}
