import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/session.dart';

/// Animated badge that replaces the plain "Done / Failed / Cancelled" chip
/// in [ProgressCard] once the session reaches a terminal state. It enters
/// with a scale-bounce and check / cross icon so the user gets immediate
/// "yes, your transfer actually worked" feedback.
class TransferOutcome extends StatefulWidget {
  const TransferOutcome({super.key, required this.status});

  final TransferStatus status;

  @override
  State<TransferOutcome> createState() => _TransferOutcomeState();
}

class _TransferOutcomeState extends State<TransferOutcome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _iconAngle;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.25), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.9), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _iconAngle = Tween<double>(begin: -0.15, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool success = widget.status == TransferStatus.completed;
    final bool cancelled = widget.status == TransferStatus.cancelled;

    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;
    if (success) {
      bg = Colors.green.withOpacity(0.12);
      fg = Colors.green;
      icon = Icons.check_circle;
      label = 'Done';
    } else if (cancelled) {
      bg = theme.colorScheme.onSurfaceVariant.withOpacity(0.12);
      fg = theme.colorScheme.onSurfaceVariant;
      icon = Icons.cancel_outlined;
      label = 'Cancelled';
    } else {
      bg = theme.colorScheme.error.withOpacity(0.12);
      fg = theme.colorScheme.error;
      icon = Icons.error;
      label = 'Failed';
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: Transform.rotate(
            angle: _iconAngle.value * math.pi,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
