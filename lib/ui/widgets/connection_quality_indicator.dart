import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/util/connection_quality.dart';
import '../../state/app_state.dart';

/// AppBar widget that shows a small 3-bar signal-style icon coloured by
/// how many peers the app currently sees. Tapping it shows a tooltip
/// with a plain-English explanation.
class ConnectionQualityIndicator extends StatelessWidget {
  const ConnectionQualityIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final quality = qualityForPeerCount(state.peers.length);
    final theme = Theme.of(context);
    final colour = _colourFor(quality, theme);
    return Tooltip(
      message: quality.label,
      child: Semantics(
        label: quality.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Bar(height: 6, filled: quality.bars >= 1, colour: colour),
              const SizedBox(width: 2),
              _Bar(height: 10, filled: quality.bars >= 2, colour: colour),
              const SizedBox(width: 2),
              _Bar(height: 14, filled: quality.bars >= 3, colour: colour),
            ],
          ),
        ),
      ),
    );
  }

  Color _colourFor(ConnectionQuality q, ThemeData theme) {
    switch (q) {
      case ConnectionQuality.none:
        return theme.colorScheme.outline;
      case ConnectionQuality.weak:
        return theme.colorScheme.error;
      case ConnectionQuality.fair:
        return theme.colorScheme.tertiary;
      case ConnectionQuality.strong:
        return theme.colorScheme.primary;
    }
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.height,
    required this.filled,
    required this.colour,
  });
  final double height;
  final bool filled;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: filled ? colour : colour.withOpacity(0.25),
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
