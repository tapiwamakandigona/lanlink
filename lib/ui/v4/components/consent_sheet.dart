import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/tokens.dart';
import 'device_radar.dart';
import 'verified_badge.dart';

/// The receive prompt: "<Name> wants to send you N files (total size)".
///
/// Friendly and calm — sender identity is a name plus an optional Verified
/// badge; there are no hashes or addresses. Designed to be hosted inside a
/// bottom sheet (`showModalBottomSheet`) or a dialog on desktop.
class ConsentSheet extends StatefulWidget {
  const ConsentSheet({
    super.key,
    required this.data,
    required this.onAccept,
    required this.onDecline,
    this.onTrustChanged,
  });

  /// What to render.
  final ConsentRequestData data;

  /// Called when the user accepts the incoming files.
  final VoidCallback onAccept;

  /// Called when the user declines.
  final VoidCallback onDecline;

  /// When non-null, shows an opt-in "Always accept from this device"
  /// checkbox (unticked by default) and reports every toggle. The caller
  /// decides what trusting means; the sheet only collects the choice.
  final ValueChanged<bool>? onTrustChanged;

  @override
  State<ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<ConsentSheet> {
  bool _trust = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final scheme = Theme.of(context).colorScheme;
    final files = data.fileCount == 1 ? '1 file' : '${data.fileCount} files';
    final preview = data.previewFileNames.take(3).toList();
    final more = data.fileCount - preview.length;

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(VSpace.x6, VSpace.x5, VSpace.x6, VSpace.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  DeviceBubble.initialsFor(data.senderName),
                  style: VType.bodyStrong
                      .copyWith(color: scheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(width: VSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            data.senderName,
                            style:
                                VType.heading.copyWith(color: scheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (data.verified) ...[
                          const SizedBox(width: VSpace.x2),
                          const VerifiedBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'wants to send you $files (${data.totalSize})',
                      style:
                          VType.body.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: VSpace.x5),
            Container(
              padding: const EdgeInsets.all(VSpace.x4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: VRadius.smAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final name in preview)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: VSpace.x1),
                      child: Row(
                        children: [
                          Icon(Icons.insert_drive_file_outlined,
                              size: 16, color: scheme.onSurfaceVariant),
                          const SizedBox(width: VSpace.x2),
                          Expanded(
                            child: Text(
                              name,
                              style:
                                  VType.body.copyWith(color: scheme.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (more > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: VSpace.x1),
                      child: Text(
                        'and $more more',
                        style: VType.caption
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (widget.onTrustChanged != null) ...[
            const SizedBox(height: VSpace.x4),
            CheckboxListTile(
              value: _trust,
              onChanged: (v) {
                setState(() => _trust = v ?? false);
                widget.onTrustChanged!(_trust);
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'Always accept from this device',
                style: VType.body.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
          const SizedBox(height: VSpace.x6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onDecline,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: VSpace.x3),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: widget.onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
