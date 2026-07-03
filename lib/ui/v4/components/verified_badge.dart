import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Small pill badge that marks a peer as verified (previously paired).
///
/// This is the ONLY way trust is shown in v4 — never a fingerprint hash.
/// Uses the brand color (trust is identity, not "success"), keeping the
/// single semantic green reserved for completed transfers.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.compact = false});

  /// When true, renders only the shield icon in a small disc — used on
  /// tight surfaces like radar bubbles.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (compact) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 2),
        ),
        child: Icon(Icons.verified_user,
            size: 11, color: scheme.onPrimaryContainer),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x2, vertical: VSpace.x1 / 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user, size: 12, color: scheme.onPrimaryContainer),
          const SizedBox(width: VSpace.x1),
          Text(
            'Verified',
            style: VType.caption.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
