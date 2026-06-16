import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Фирменная диагональная полоска-«скотч» (orange / ink) из шапки прототипа.
class TapeStripe extends StatelessWidget {
  const TapeStripe({super.key, this.height = 4});

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _TapePainter(c.orange, c.ink)),
    );
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter(this.orange, this.ink);
  final Color orange;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const stripe = 14.0; // ширина полоски по прототипу
    final paintO = Paint()..color = orange;
    final paintI = Paint()..color = ink;
    // Диагональные полосы под 135°
    canvas.clipRect(Offset.zero & size);
    for (double x = -size.height; x < size.width + size.height; x += stripe * 2) {
      _band(canvas, x, size, stripe, paintO);
      _band(canvas, x + stripe, size, stripe, paintI);
    }
  }

  void _band(Canvas canvas, double x, Size size, double w, Paint p) {
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x + w, 0)
      ..lineTo(x + w - size.height, size.height)
      ..lineTo(x - size.height, size.height)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _TapePainter old) =>
      old.orange != orange || old.ink != ink;
}
