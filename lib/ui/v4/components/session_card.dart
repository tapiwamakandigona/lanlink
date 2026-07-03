import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/tokens.dart';

/// One transfer session: file summary, size, progress, live speed + ETA,
/// a status chip, and state-appropriate actions.
///
/// Actions by state:
///  * waiting / transferring → **Stop** ([onStop])
///  * failed → **Try again** ([onRetry]) + **Dismiss**
///  * sent / cancelled → **Dismiss** ([onDismiss])
///
/// Terminal states are visually distinct: Sent! uses the single semantic
/// success green, Failed the danger red, Cancelled a neutral chip.
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.data,
    this.onStop,
    this.onRetry,
    this.onDismiss,
    this.onLocate,
  });

  /// What to render.
  final SessionCardData data;

  /// Shown while waiting/transferring.
  final VoidCallback? onStop;

  /// Shown when failed. When null (e.g. the session cannot be retried),
  /// the "Try again" action is hidden entirely.
  final VoidCallback? onRetry;

  /// Shown on any terminal state.
  final VoidCallback? onDismiss;

  /// Optional "Where is it?" action for completed receives; shown only
  /// when non-null and the session finished successfully.
  final VoidCallback? onLocate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ember = context.ember;
    final status = data.status;

    final fileCountLabel = '${data.fileCount} files';
    final receive = data.direction == SessionDirection.receive;
    final subtitleParts = <String>[
      // Don't repeat the file count when the title already is the count
      // ("14 files" as both title and subtitle).
      if (data.fileCount > 1 && data.title != fileCountLabel) fileCountLabel,
      data.totalSize,
      if (data.peerName != null)
        status == SessionStatus.sent
            ? (receive ? 'from ${data.peerName}' : 'to ${data.peerName}')
            : '${data.peerName}',
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: VRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(VSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LeadingIcon(status: status),
              const SizedBox(width: VSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: VType.bodyStrong.copyWith(color: scheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' · '),
                      style: VType.caption
                          .copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: VSpace.x3),
              SessionStatusChip(status: status, direction: data.direction),
            ],
          ),
          if (status == SessionStatus.transferring ||
              status == SessionStatus.waiting) ...[
            const SizedBox(height: VSpace.x4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: status == SessionStatus.waiting ? null : data.progress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: VSpace.x2),
            Row(
              children: [
                if (status == SessionStatus.waiting)
                  Text(
                    'Waiting for them to accept…',
                    style:
                        VType.caption.copyWith(color: scheme.onSurfaceVariant),
                  )
                else ...[
                  if (data.speed != null)
                    Text(
                      data.speed!,
                      style: VType.numeric.copyWith(color: scheme.onSurface),
                    ),
                  if (data.speed != null && data.eta != null)
                    Text(
                      '  ·  ',
                      style: VType.caption
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  if (data.eta != null)
                    Expanded(
                      child: Text(
                        data.eta!,
                        style: VType.caption
                            .copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                ],
                if (status == SessionStatus.waiting) const Spacer(),
                if (data.progress != null &&
                    status == SessionStatus.transferring)
                  Text(
                    '${(data.progress!.clamp(0, 1) * 100).round()}%',
                    style:
                        VType.numeric.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ],
          if (status == SessionStatus.failed && data.errorHint != null) ...[
            const SizedBox(height: VSpace.x3),
            Text(
              data.errorHint!,
              style: VType.caption.copyWith(color: ember.danger),
            ),
          ],
          const SizedBox(height: VSpace.x1),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: VSpace.x2,
              runSpacing: VSpace.x2,
              children: [
                if (!status.isTerminal)
                  TextButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    style: TextButton.styleFrom(foregroundColor: ember.danger),
                    label: const Text('Stop'),
                  ),
                if (status == SessionStatus.failed) ...[
                  TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant),
                    child: const Text('Dismiss'),
                  ),
                  if (onRetry != null)
                    FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try again'),
                    ),
                ],
                if (status == SessionStatus.sent && onLocate != null)
                  TextButton.icon(
                    onPressed: onLocate,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Where is it?'),
                  ),
                if (status == SessionStatus.sent ||
                    status == SessionStatus.cancelled)
                  TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant),
                    child: const Text('Dismiss'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The status chip used on [SessionCard]; exported for reuse in lists.
class SessionStatusChip extends StatelessWidget {
  const SessionStatusChip({
    super.key,
    required this.status,
    this.direction = SessionDirection.send,
  });

  /// Which state to render.
  final SessionStatus status;

  /// Which way the bytes move; receive sessions read "Receiving" /
  /// "Received!" instead of "Sending" / "Sent!".
  final SessionDirection direction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ember = context.ember;
    final receive = direction == SessionDirection.receive;

    final (String label, Color bg, Color fg) = switch (status) {
      SessionStatus.waiting => (
          'Waiting',
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        ),
      SessionStatus.transferring => (
          receive ? 'Receiving' : 'Sending',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      SessionStatus.sent => (
          receive ? 'Received!' : 'Sent!',
          ember.successContainer,
          ember.onSuccessContainer,
        ),
      SessionStatus.failed => (
          'Failed',
          ember.dangerContainer,
          ember.onDangerContainer,
        ),
      SessionStatus.cancelled => (
          'Cancelled',
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x3, vertical: VSpace.x1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: VType.label.copyWith(color: fg)),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ember = context.ember;
    final (IconData icon, Color bg, Color fg) = switch (status) {
      SessionStatus.sent => (
          Icons.check,
          ember.successContainer,
          ember.onSuccessContainer,
        ),
      SessionStatus.failed => (
          Icons.priority_high,
          ember.dangerContainer,
          ember.onDangerContainer,
        ),
      SessionStatus.cancelled => (
          Icons.block,
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        ),
      _ => (
          Icons.description_outlined,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: VRadius.smAll,
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}
