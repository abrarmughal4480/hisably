import 'package:flutter/material.dart';

import '../theme/hisably_theme.dart';

/// The Hisably mark: a green gradient "H" with NO background
/// (final logo approved by the user, 22 Oct 2026).
class HisablyLogo extends StatelessWidget {
  const HisablyLogo({super.key, this.size = 78});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LogoPainter(),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final u = w / 96; // design grid 96x96
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4ADE80), HisablyColors.logoGreenDeep],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11 * u
      ..strokeCap = StrokeCap.round;
    // Left stem, right stem, crossbar — the letter H.
    canvas.drawLine(Offset(30 * u, 20 * u), Offset(30 * u, 76 * u), paint);
    canvas.drawLine(Offset(66 * u, 20 * u), Offset(66 * u, 76 * u), paint);
    canvas.drawLine(Offset(30 * u, 48 * u), Offset(66 * u, 48 * u), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
