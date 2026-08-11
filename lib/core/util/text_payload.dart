import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/file_info.dart';

const _uuid = Uuid();

/// Stages a text snippet (link, password, note) as a sendable [FileInfo].
///
/// The LocalSend v2 wire protocol only moves files, so the snippet is
/// written to a small `.txt` in [tempDir] and sent like any other file.
/// The name carries a timestamp so repeated messages never collide on the
/// receiver ("Message 2026-08-11 13.42.07.txt").
Future<FileInfo> stageTextSnippet(String text, Directory tempDir) async {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}.${two(now.minute)}.${two(now.second)}';
  final file = File('${tempDir.path}${Platform.pathSeparator}'
      'Message $stamp.txt');
  await file.writeAsString(text, flush: true);
  final size = await file.length();
  return FileInfo(
    id: _uuid.v4(),
    fileName: 'Message $stamp.txt',
    size: size,
    fileType: 'text',
    localPath: file.path,
  );
}

/// Whether a received file looks like a LanLink text-message snippet:
/// small `.txt` named `Message …` with fileType `text`. Drives the
/// receiver-side "Copy message" affordance.
bool isMessageSnippet(FileInfo file) =>
    file.fileType == 'text' &&
    file.fileName.startsWith('Message ') &&
    file.fileName.endsWith('.txt') &&
    file.size <= 64 * 1024;
