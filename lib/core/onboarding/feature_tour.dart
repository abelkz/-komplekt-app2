import 'package:flutter/material.dart';

import '../config/local_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Шаг тура: какой элемент подсветить и что о нём рассказать.
class TourStep {
  const TourStep({required this.key, required this.title, required this.text});

  final GlobalKey key;
  final String title;
  final String text;
}

/// Ключи элементов, которые показываются в турах.
/// Живут здесь, чтобы экран и тур не зависели друг от друга напрямую.
class TourKeys {
  TourKeys._();

  // Главная
  static final search = GlobalKey(debugLabel: 'tour-search');
  static final map = GlobalKey(debugLabel: 'tour-map');
  static final bell = GlobalKey(debugLabel: 'tour-bell');
  static final navBar = GlobalKey(debugLabel: 'tour-nav');

  // Кабинет поставщика
  static final cabImport = GlobalKey(debugLabel: 'tour-cab-import');
  static final cabAdd = GlobalKey(debugLabel: 'tour-cab-add');
  static final cabLocation = GlobalKey(debugLabel: 'tour-cab-location');
  static final cabProfile = GlobalKey(debugLabel: 'tour-cab-profile');
  static final cabPro = GlobalKey(debugLabel: 'tour-cab-pro');
}

/// Знакомство с приложением: затемнённый фон, «окно» вокруг элемента
/// с жёлтой рамкой и карточка с пояснением. «Далее» ведёт по шагам,
/// «Пропустить» закрывает. Каждый тур показывается один раз —
/// отметка хранится на устройстве.
class FeatureTour {
  FeatureTour._();

  static Future<void> maybeShow(
    BuildContext context, {
    required LocalStore store,
    required String id,
    required List<TourStep> steps,
  }) async {
    if (store.tourSeen(id)) return;

    // Берём только шаги, чьи элементы реально есть на экране
    final valid = steps.where((s) => s.key.currentContext != null).toList();
    if (valid.isEmpty) return;

    // Отмечаем сразу: даже если тур закроют системной «назад»,
    // он не будет навязываться при каждом входе.
    await store.setTourSeen(id);
    if (!context.mounted) return;

    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, __, ___) => _TourOverlay(steps: valid),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps});
  final List<TourStep> steps;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _i = 0;

  TourStep get _step => widget.steps[_i];

  Rect? _rectOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _next() async {
    if (_i >= widget.steps.length - 1) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final next = widget.steps[_i + 1];
    // Элемент может быть ниже по прокрутке — подвозим его в кадр
    final ctx = next.key.currentContext;
    if (ctx != null) {
      try {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.4,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {/* элемент вне прокрутки — и не надо */}
    }
    if (mounted) setState(() => _i++);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final screen = MediaQuery.sizeOf(context);
    final rect = _rectOf(_step.key)?.inflate(6);

    // Элемент исчез между шагами — просто идём дальше
    if (rect == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _next());
      return const SizedBox.shrink();
    }

    // Карточка с текстом: под элементом, если он в верхней половине,
    // иначе над ним
    final below = rect.center.dy < screen.height * 0.55;

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _next,
        child: Stack(
          children: [
            // Затемнение с «окном»
            Positioned.fill(
              child: CustomPaint(
                painter: _HolePainter(hole: rect),
              ),
            ),
            // Карточка с пояснением
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              left: 16,
              right: 16,
              top: below ? rect.bottom + 14 : null,
              bottom: below ? null : screen.height - rect.top + 14,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _StepCard(
                  key: ValueKey(_i),
                  step: _step,
                  index: _i,
                  total: widget.steps.length,
                  onNext: _next,
                  onSkip: () => Navigator.of(context).pop(),
                  colors: c,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
    required this.colors,
  });

  final TourStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final last = index == total - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandYellow, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(step.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(step.text,
              style: TextStyle(
                  fontSize: 13.5, height: 1.4, color: colors.gray)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('${index + 1} / $total',
                  style: AppTypography.mono(size: 11, color: colors.faint)),
              const Spacer(),
              if (!last)
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(foregroundColor: colors.gray),
                  child: const Text('Пропустить'),
                ),
              const SizedBox(width: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandYellow,
                  foregroundColor: AppColors.brandInk,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: onNext,
                child: Text(last ? 'Понятно' : 'Далее'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Затемнение всего экрана с прозрачным «окном» вокруг элемента.
class _HolePainter extends CustomPainter {
  _HolePainter({required this.hole});
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(hole, const Radius.circular(10));

    canvas.saveLayer(full, Paint());
    canvas.drawRect(full, Paint()..color = Colors.black.withValues(alpha: 0.72));
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.brandYellow,
    );
  }

  @override
  bool shouldRepaint(covariant _HolePainter old) => old.hole != hole;
}
