import 'package:flutter/material.dart';

import '../../core/models/session.dart';
import '../../core/util/format.dart';

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
                      child: Text(
                        '${session.direction == TransferDirection.send ? "Sending to" : "Receiving from"} '
                        '${session.peer.alias}',
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _statusBadge(context),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: 8),
                Text(
                  _summary(speed),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                for (final f in session.files.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
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
    late final String text;
    late final Color color;
    switch (session.status) {
      case TransferStatus.transferring:
      case TransferStatus.awaitingAccept:
        text = session.status == TransferStatus.awaitingAccept
            ? 'Waiting'
            : 'In progress';
        color = theme.colorScheme.primary;
        break;
      case TransferStatus.completed:
        text = 'Done';
        color = Colors.green;
        break;
      case TransferStatus.failed:
        text = 'Failed';
        color = theme.colorScheme.error;
        break;
      case TransferStatus.cancelled:
        text = 'Cancelled';
        color = theme.colorScheme.onSurfaceVariant;
        break;
    }
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
    final eta = formatEta(session.totalBytes, session.transferredBytes, speed);
    final parts = <String>[
      '${formatBytes(session.transferredBytes)} / ${formatBytes(session.totalBytes)}',
      if (speed > 0) formatSpeed(speed),
      if (eta.isNotEmpty) 'ETA $eta',
    ];
    return parts.join(' • ');
  }
}
