import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Рисует «измерительную ленту» — частые мелкие деления и редкие крупные.
/// Фирменный элемент дизайна «Спецификация»: линейка вместо декоративной
/// плашки. Используется и в шапке экранов, и в нижней навигации.
class RulerPainter extends CustomPainter {
  const RulerPainter({
    required this.color,
    this.minorStep = 7,
    this.majorStep = 35,
  });

  /// Цвет делений; прозрачность мелких и крупных подбирается автоматически.
  final Color color;
  final double minorStep;
  final double majorStep;

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1.5;

    for (double x = 0; x <= size.width; x += minorStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
    }
    for (double x = 0; x <= size.width; x += majorStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
    }
  }

  @override
  bool shouldRepaint(covariant RulerPainter old) =>
      old.color != color ||
      old.minorStep != minorStep ||
      old.majorStep != majorStep;
}

/// Фирменная лента-линейка в шапке экрана.
/// Имя класса сохранено с прошлой версии дизайна, чтобы не трогать экраны,
/// которые её уже показывают.
class TapeStripe extends StatelessWidget {
  const TapeStripe({super.key, this.height = 12});

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: RulerPainter(color: c.ink)),
      ),
    );
  }
}

/// Тёмная лента для нижней навигации: деления цветом кости на туши.
class DarkRuler extends StatelessWidget {
  const DarkRuler({super.key, this.height = 14});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: const CustomPaint(
          painter: RulerPainter(color: AppColors.brandBone),
        ),
      );
}
