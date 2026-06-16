import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/tape_stripe.dart';

/// Экран 1 — приветствие и выбор города запуска.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _cities = [
    'Астана',
    'Алматы',
    'Шымкент',
    'Караганда',
    'Атырау',
  ];
  String _selected = 'Астана';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Column(
        children: [
          const TapeStripe(),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('КОМПЛЕКТ', style: AppTypography.unbounded(size: 28)),
                    const SizedBox(height: 8),
                    Text(
                      'Цены поставщиков отделочных материалов — '
                      'в одном приложении. Сравнивайте, собирайте подборки, '
                      'находите магазины рядом.',
                      style: TextStyle(fontSize: 14, color: c.gray, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    Text('Ваш город',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                            color: c.faint)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _cities.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 9),
                        itemBuilder: (_, i) {
                          final city = _cities[i];
                          final on = city == _selected;
                          return InkWell(
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            onTap: () => setState(() => _selected = city),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: on ? c.orangeSoft : c.card,
                                border: Border.all(
                                    color: on ? c.orange : c.line,
                                    width: on ? 1.5 : 1),
                                borderRadius:
                                    BorderRadius.circular(AppRadii.md),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_outlined,
                                      size: 20,
                                      color: on ? c.orange : c.gray),
                                  const SizedBox(width: 12),
                                  Text(city,
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: on ? c.orange : c.ink)),
                                  const Spacer(),
                                  if (on)
                                    Icon(Icons.check_circle,
                                        color: c.orange, size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => ref
                            .read(settingsProvider.notifier)
                            .completeOnboarding(_selected),
                        child: const Text('Продолжить'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
