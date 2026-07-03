import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/tokens.dart';

/// Receive side: shows this device's pairing QR on a paper card with a
/// friendly caption. The [payload] is opaque to this component.
class QrDisplayPanel extends StatelessWidget {
  const QrDisplayPanel({
    super.key,
    required this.payload,
    required this.deviceName,
    this.size = 208,
  });

  /// The string encoded into the QR (connection payload; opaque here).
  final String payload;

  /// This device's friendly name, shown under the code.
  final String deviceName;

  /// Rendered QR edge length in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(VSpace.x6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: VRadius.lgAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(VSpace.x3),
            decoration: const BoxDecoration(
              // The QR itself stays on a pure light plate in BOTH themes so
              // any camera can read it (see VQr tokens).
              color: VQr.plate,
              borderRadius: VRadius.smAll,
            ),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: size,
              gapless: true,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: VQr.ink,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: VQr.ink,
              ),
            ),
          ),
          const SizedBox(height: VSpace.x4),
          Text(
            deviceName,
            style: VType.bodyStrong.copyWith(color: scheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VSpace.x1),
          Text(
            'Scan this from the sending device',
            style: VType.caption.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Send side: a viewfinder frame with copper corner brackets that overlays
/// a camera preview. The preview itself is injected via [child] so this
/// component stays free of camera plugins.
class QrScanFrame extends StatelessWidget {
  const QrScanFrame({
    super.key,
    this.child,
    this.hint = 'Point at the code on the receiving device',
  });

  /// The live camera preview (or a placeholder in the gallery/tests).
  final Widget? child;

  /// One calm sentence under the frame.
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: VRadius.lgAll,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: child ??
                      Center(
                        child: Icon(Icons.qr_code_scanner,
                            size: 40, color: scheme.onSurfaceVariant),
                      ),
                ),
                Padding(
                  padding: const EdgeInsets.all(VSpace.x6),
                  child: CustomPaint(
                    painter: _CornerBracketsPainter(color: scheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VSpace.x4),
        Text(
          hint,
          style: VType.body.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _CornerBracketsPainter extends CustomPainter {
  _CornerBracketsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    const r = 14.0;
    final w = size.width;
    final h = size.height;

    // An L-bracket from [a] to [b] whose elbow at corner point [c] is
    // rounded with radius [r].
    Path corner(Offset a, Offset c, Offset b) {
      Offset towards(Offset from, Offset to, double d) {
        final v = to - from;
        final scale = d / v.distance;
        return from + Offset(v.dx * scale, v.dy * scale);
      }

      final inA = towards(c, a, r);
      final inB = towards(c, b, r);
      return Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(inA.dx, inA.dy)
        ..quadraticBezierTo(c.dx, c.dy, inB.dx, inB.dy)
        ..lineTo(b.dx, b.dy);
    }

    canvas.drawPath(
        corner(const Offset(0, len), const Offset(0, 0), const Offset(len, 0)),
        paint);
    canvas.drawPath(
        corner(Offset(w - len, 0), Offset(w, 0), Offset(w, len)), paint);
    canvas.drawPath(
        corner(Offset(w, h - len), Offset(w, h), Offset(w - len, h)), paint);
    canvas.drawPath(
        corner(Offset(len, h), Offset(0, h), Offset(0, h - len)), paint);
  }

  @override
  bool shouldRepaint(_CornerBracketsPainter old) => old.color != color;
}
