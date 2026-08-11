import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/models/file_info.dart';
import '../../core/models/session.dart';
import '../../core/platform/reveal_folder.dart';
import '../../core/util/text_payload.dart';

/// The folder a completed receive [session] landed in, derived from the
/// first saved file's path. Null when no file recorded a saved path.
String? savedFolderFor(TransferSession session) {
  for (final f in session.files.values) {
    final path = f.savedPath;
    if (path != null && path.isNotEmpty) return p.dirname(path);
  }
  return null;
}

/// The saved path of the single received file, or null when the session
/// saved zero or multiple files. Drives the one-tap "Open file" action —
/// only a lone file has an unambiguous thing to open.
String? singleSavedFileFor(TransferSession session) {
  String? only;
  for (final f in session.files.values) {
    final path = f.savedPath;
    if (path == null || path.isEmpty) continue;
    if (only != null) return null;
    only = path;
  }
  return only;
}

/// The [FileInfo] of the single saved file, or null when the session
/// saved zero or multiple files. Companion to [singleSavedFileFor] for
/// callers that need metadata (type, name), not just the path.
FileInfo? singleSavedFileInfoFor(TransferSession session) {
  FileInfo? only;
  for (final f in session.files.values) {
    final path = f.savedPath;
    if (path == null || path.isEmpty) continue;
    if (only != null) return null;
    only = f.file;
  }
  return only;
}

/// Lightweight "Where is it?" affordance: a dialog with the actual save
/// location and a copy button. On Android it also notes the Downloads
/// publish, since file paths there are not user-navigable.
Future<void> showSavedLocationDialog(
    BuildContext context, TransferSession session) {
  final folder = savedFolderFor(session);
  final singleFile = singleSavedFileFor(session);
  final singleInfo = singleSavedFileInfoFor(session);
  final isMessage =
      singleFile != null && singleInfo != null && isMessageSnippet(singleInfo);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Where your files are'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMessage) ...[
            FutureBuilder<String>(
              future: File(singleFile).readAsString(),
              builder: (ctx, snap) => Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  snap.data ?? '…',
                  maxLines: 8,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (folder != null)
            SelectableText(folder)
          else
            const Text('The save location was not recorded for this '
                'transfer. Check the save folder shown in Settings.'),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 12),
            Text(
              'On Android, received files also appear in your Downloads.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        if (isMessage)
          FilledButton.tonalIcon(
            icon: const Icon(Icons.copy_all, size: 18),
            label: const Text('Copy message'),
            onPressed: () async {
              final text = await File(singleFile).readAsString();
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        if (folder != null)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy path'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: folder));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        // Desktop gets a real "Open folder" — competing tools jump
        // straight to the received files, a copyable path is the fallback.
        if (folder != null &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ...[
          TextButton.icon(
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('Open folder'),
            onPressed: () {
              unawaited(revealFolder(folder));
              Navigator.of(ctx).pop();
            },
          ),
          // A lone received file opens directly — the AirDrop / Quick
          // Share one-tap. Ambiguous (multi-file) sessions only offer
          // the folder.
          if (singleFile != null)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open file'),
              onPressed: () {
                unawaited(openFile(singleFile));
                Navigator.of(ctx).pop();
              },
            ),
        ],
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
