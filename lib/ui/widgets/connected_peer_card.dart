import 'package:flutter/material.dart';

import '../v4/v4.dart';

/// The symmetric-session strip (F3): shown on home for every linked peer.
///
/// Once two devices pair — QR token, Direct Link, or an accepted transfer —
/// both sides get this card, so either can send files back without
/// re-scanning, and either can end the session with Disconnect.
class ConnectedPeerCard extends StatelessWidget {
  const ConnectedPeerCard({
    super.key,
    required this.peerName,
    required this.onSendFiles,
    required this.onDisconnect,
    this.verified = false,
  });

  /// Display name of the linked peer.
  final String peerName;

  /// Opens the send flow already pointed at this peer.
  final VoidCallback onSendFiles;

  /// Ends the session on both sides.
  final VoidCallback onDisconnect;

  /// Whether the peer's fingerprint is pinned (QR/Direct Link pairing).
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ember = context.ember;
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
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: VRadius.smAll,
                ),
                child: Icon(
                  Icons.swap_horiz,
                  size: 20,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: VSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            peerName,
                            style: VType.bodyStrong
                                .copyWith(color: scheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: VSpace.x2),
                          const VerifiedBadge(compact: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Connected — either of you can send.',
                      style: VType.caption
                          .copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: VSpace.x3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off, size: 18),
                style: TextButton.styleFrom(foregroundColor: ember.danger),
                label: const Text('Disconnect'),
              ),
              const SizedBox(width: VSpace.x2),
              FilledButton.tonalIcon(
                onPressed: onSendFiles,
                icon: const Icon(Icons.arrow_upward, size: 18),
                label: const Text('Send files'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
