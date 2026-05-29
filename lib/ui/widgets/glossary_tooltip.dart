import 'package:flutter/material.dart';

/// Small inline ⓘ icon that pops a plain-English explanation when
/// tapped. Used next to settings labels that previously read like
/// debug-log entries ("fingerprint", "subnet", "MDNS"…) to keep the
/// surface friendly without dumbing-down the controls for power users.
class GlossaryTooltip extends StatelessWidget {
  const GlossaryTooltip({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Builder(
      builder: (innerContext) {
        return Tooltip(
          message: message,
          preferBelow: false,
          triggerMode: TooltipTriggerMode.tap,
          padding: const EdgeInsets.all(12),
          textStyle: TextStyle(
            color: theme.colorScheme.onInverseSurface,
            fontSize: 13,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}
