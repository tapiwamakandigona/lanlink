import 'dart:math';

import 'package:flutter/material.dart';

/// Small, asset-free "first successful transfer" celebration: a
/// bouncing checkmark with a burst of confetti dots. Drawn entirely in
/// Flutter so it doesn't bloat the APK or rely on Lottie.
class SuccessCelebration extends StatefulWidget {
  const SuccessCelebration({
    super.key,
    this.size = 120,
    this.duration = const Duration(milliseconds: 1400),
  });
  final double size;
  final Duration duration;

  @override
  State<SuccessCelebration> createState() => _SuccessCelebrationState();
}

class _SuccessCelebrationState extends State<SuccessCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (context, _) {
          return CustomPaint(
            painter: _ConfettiPainter(
              progress: _ctl.value,
              accent: theme.colorScheme.primary,
              accent2: theme.colorScheme.tertiary,
              accent3: theme.colorScheme.secondary,
            ),
            child: Center(
              child: Transform.scale(
                scale: _bounceScale(_ctl.value),
                child: Container(
                  width: widget.size * 0.55,
                  height: widget.size * 0.55,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.35),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.check,
                    size: widget.size * 0.32,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  double _bounceScale(double t) {
    // 0 → 1 → 1.15 → 1.0 mild overshoot bounce.
    if (t < 0.5) return Curves.easeOutBack.transform(t * 2);
    if (t < 0.65) return 1 + 0.15 * ((t - 0.5) / 0.15);
    return 1.15 - 0.15 * ((t - 0.65) / 0.35);
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.progress,
    required this.accent,
    required this.accent2,
    required this.accent3,
  });

  final double progress;
  final Color accent;
  final Color accent2;
  final Color accent3;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final colours = [accent, accent2, accent3];
    final rng = Random(7);
    const dots = 14;
    for (int i = 0; i < dots; i++) {
      final angle = (i / dots) * 2 * pi + rng.nextDouble() * 0.4;
      final maxR = size.width * (0.45 + rng.nextDouble() * 0.2);
      final r = maxR * Curves.easeOut.transform(progress);
      final offset = Offset(
        centre.dx + cos(angle) * r,
        centre.dy + sin(angle) * r,
      );
      final paint = Paint()
        ..color = colours[i % colours.length]
            .withOpacity((1 - progress).clamp(0, 1).toDouble());
      canvas.drawCircle(offset, 3.5, paint);
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
