import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/session.dart';
import '../../core/util/eta.dart';
import '../../core/util/format.dart';
import '../../state/app_state.dart';
import 'transfer_outcome.dart';

/// Compact progress UI for a single [TransferSession].
class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.session});

  final TransferSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final fraction = session.fraction.clamp(0.0, 1.0);
        final speed = session.speedBytesPerSec;
        final eta = plainEnglishEta(
          totalBytes: session.totalBytes,
          doneBytes: session.transferredBytes,
          bytesPerSec: speed,
        );
        final slow = isSlowSpeed(speed) &&
            session.status == TransferStatus.transferring &&
            session.transferredBytes > 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      session.direction == TransferDirection.send
                          ? Icons.upload
                          : Icons.download,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Builder(
                        builder: (innerCtx) {
                          final settings = innerCtx.watch<AppState>().settings;
                          final name =
                              settings.nicknameFor(session.peer.fingerprint) ??
                                  (session.peer.alias.isEmpty
                                      ? 'Unknown device'
                                      : session.peer.alias);
                          return Text(
                            '${session.direction == TransferDirection.send ? "Sending to" : "Receiving from"} '
                            '$name',
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ),
                    _statusBadge(context),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: 8),
                if (eta.isNotEmpty)
                  Text(
                    eta,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  _summary(speed),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (slow) ...[
                  const SizedBox(height: 8),
                  _SlowWarning(),
                ],
                const SizedBox(height: 6),
                for (final f in session.files.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FileThumb(file: f),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      f.file.fileName,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${formatBytes(f.bytes)} / ${formatBytes(f.file.size)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              if (f.savedPath != null &&
                                  f.savedPath!.isNotEmpty)
                                Text(
                                  'Saved to ${f.savedPath}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (f.error != null && f.error!.isNotEmpty)
                                Text(
                                  f.error!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusBadge(BuildContext context) {
    final theme = Theme.of(context);
    if (session.status == TransferStatus.completed ||
        session.status == TransferStatus.failed ||
        session.status == TransferStatus.cancelled) {
      return TransferOutcome(
        key: ValueKey('${session.sessionId}-${session.status.name}'),
        status: session.status,
      );
    }
    final text = session.status == TransferStatus.awaitingAccept
        ? 'Waiting'
        : 'In progress';
    final color = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child:
          Text(text, style: theme.textTheme.labelSmall?.copyWith(color: color)),
    );
  }

  String _summary(double speed) {
    final parts = <String>[
      '${formatBytes(session.transferredBytes)} of ${formatBytes(session.totalBytes)}',
      if (speed > 0) formatSpeed(speed),
    ];
    return parts.join('  •  ');
  }
}

class _SlowWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_tethering_error,
              size: 18, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Connection is slow — try moving the two devices closer "
              'together.',
              style: TextStyle(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small thumbnail next to each file row. For images we show the actual
/// bitmap (sender-side) or the in-flight preview saved-path (receiver,
/// once the file has been fully written). For everything else we show a
/// rounded icon keyed off [FileInfo.fileType] — much friendlier than
/// just the filename on its own.
class _FileThumb extends StatelessWidget {
  const _FileThumb({required this.file});
  final FileProgress file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fi = file.file;
    Widget child;
    final imagePath = _imagePath();
    if (imagePath != null) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(imagePath),
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconBox(theme, fi.fileType),
          cacheHeight: 96,
        ),
      );
    } else {
      child = _iconBox(theme, fi.fileType);
    }
    return SizedBox(width: 36, height: 36, child: child);
  }

  String? _imagePath() {
    if (file.file.fileType != 'image') return null;
    final path = file.file.localPath ?? file.savedPath;
    if (path == null || path.isEmpty) return null;
    final f = File(path);
    if (!f.existsSync()) return null;
    return path;
  }

  Widget _iconBox(ThemeData theme, String fileType) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        _iconFor(fileType),
        size: 20,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }

  IconData _iconFor(String fileType) {
    switch (fileType) {
      case 'image':
        return Icons.image_outlined;
      case 'video':
        return Icons.movie_outlined;
      case 'audio':
        return Icons.audiotrack_outlined;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'app':
        return Icons.android;
      case 'archive':
        return Icons.folder_zip_outlined;
      case 'text':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
