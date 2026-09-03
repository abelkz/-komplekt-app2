import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/build_info.dart';
import '../../../core/providers/data_refresh.dart';
import '../../../core/providers/providers.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/launchers.dart';
import '../../admin/presentation/admin_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../favorites/presentation/favorites_providers.dart';

/// Экран 8 — Профиль пользователя.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(myProfileProvider);
    final settings = ref.watch(settingsProvider);
    final favCount = ref.watch(favoriteIdsProvider).valueOrNull?.length ?? 0;
    final recentCount = ref.watch(recentSearchesProvider).length;
    // Пункт панели — только для администратора; число рядом показывает,
    // сколько заявок ждёт решения
    final isAdmin = ref.watch(isAdminProvider);
    final adminTodo = isAdmin ? ref.watch(adminPendingCountProvider) : 0;

    final name = profile.valueOrNull?.fullName.isNotEmpty == true
        ? profile.valueOrNull!.fullName
        : 'Пользователь';
    final initials = profile.valueOrNull?.initials ?? 'П';

    return Scaffold(
      body: SafeArea(
        // Потянуть вниз — перечитать профиль: так виден только что
        // включённый тариф, без перезапуска приложения
        child: RefreshIndicator(
          onRefresh: () async => refreshAppData(ref),
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Text('Профиль', style: AppTypography.unbounded()),
            const SizedBox(height: 14),

            // Карточка пользователя
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.card,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.orangeSoft,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.orange, width: 2),
                    ),
                    child: Text(initials,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: c.orange)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text('Город: ${settings.city}',
                            style: TextStyle(fontSize: 12, color: c.gray)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Кабинет поставщика — отдельной заметной карточкой
            _CabinetCard(
              isSupplier: profile.valueOrNull?.isSupplier == true,
              onTap: () => context.push(Routes.supplierCabinet),
            ),
            const SizedBox(height: 22),

            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text('НАСТРОЙКИ',
                  style: AppTypography.sectionLabel(color: c.faint)),
            ),

            // Меню
            _MenuCard(items: [
              _MenuItemData('Сменить город', settings.city,
                  icon: Icons.location_on_outlined,
                  onTap: () => _cityDialog(context, ref)),
              _MenuItemData(
                'Тёмная тема',
                settings.themeMode == ThemeMode.dark ? 'вкл' : 'выкл',
                icon: Icons.dark_mode_outlined,
                trailing: Switch(
                  value: settings.themeMode == ThemeMode.dark,
                  activeColor: c.orange,
                  onChanged: (_) =>
                      ref.read(settingsProvider.notifier).toggleTheme(),
                ),
              ),
              _MenuItemData(
                'Уведомления о ценах',
                '$favCount товаров',
                icon: Icons.notifications_none_rounded,
                onTap: () => context.push(Routes.notifications),
              ),
              _MenuItemData(
                'Настройки уведомлений',
                settings.notifyEnabled
                    ? 'порог ${settings.notifyThreshold}%'
                    : 'выкл',
                icon: Icons.tune_rounded,
                onTap: () => _notifyDialog(context, ref),
              ),
              _MenuItemData(
                'История поиска',
                '$recentCount запросов',
                icon: Icons.history_rounded,
                onTap: () => _recentSearchesSheet(context, ref),
              ),
              // Пункт есть только у администратора: остальным база всё
              // равно ничего не отдаст, но и показывать его незачем
              if (isAdmin)
                _MenuItemData(
                  'Панель администратора',
                  adminTodo == 0 ? 'заявки и тарифы' : 'ждут решения: $adminTodo',
                  icon: Icons.shield_outlined,
                  onTap: () => context.push(Routes.admin),
                ),
            ]),
            const SizedBox(height: 16),

            // Pro-апселл — открывает описание тарифа и оформление
            InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: () => context.push(Routes.plans()),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c.orange, Color.lerp(c.orange, Colors.white, 0.28)!],
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.brandInk.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.workspace_premium_rounded,
                                  size: 14, color: AppColors.brandInk),
                              const SizedBox(width: 5),
                              Text(
                                profile.valueOrNull?.isPro == true
                                    ? 'PRO АККАУНТ'
                                    : 'КОМПЛЕКТ PRO',
                                style: AppTypography.sectionLabel(
                                        color: AppColors.brandInk)
                                    .copyWith(fontSize: 10, letterSpacing: 0.4),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.verified_user_rounded,
                            size: 22, color: AppColors.brandInk),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile.valueOrNull?.isPro == true
                          ? 'Премиум-доступ'
                          : 'Больше возможностей',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppColors.brandInk),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.valueOrNull?.isPro == true
                          ? _proUntilText(profile.valueOrNull!.planUntil)
                          : 'Брендированные PDF-спецификации, история цен '
                              'и безлимитные подборки — 4 900 ₸/мес.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.brandInk.withOpacity(0.85),
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.ink,
                side: BorderSide(color: c.line),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Выйти'),
              // Ждём выхода и сразу уходим на экран входа: иначе редирект
              // по сессии срабатывал на такт позже, и выход требовал двух
              // нажатий.
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).signOut();
                if (context.mounted) context.go(Routes.auth);
              },
            ),
            const SizedBox(height: 10),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: c.red),
              onPressed: () => _deleteAccountDialog(context, ref),
              child: const Text('Удалить аккаунт'),
            ),
            const SizedBox(height: 18),
            // Документы обязаны быть доступны из приложения — это требование
            // App Store и Google Play, а по закону о персональных данных
            // человек должен видеть, на что он согласился.
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: () =>
                        Launchers.website('https://abelkz.github.io/komplekt/privacy.html'),
                    child: Text('Политика конфиденциальности',
                        style: TextStyle(fontSize: 12, color: c.gray)),
                  ),
                  TextButton(
                    onPressed: () =>
                        Launchers.website('https://abelkz.github.io/komplekt/terms.html'),
                    child: Text('Условия использования',
                        style: TextStyle(fontSize: 12, color: c.gray)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // По этой строке видно, свежая версия открыта или старая из кэша
            Center(
              child: Text(BuildInfo.label,
                  style: TextStyle(fontSize: 11, color: c.faint)),
            ),
          ],
          ),
        ),
      ),
    );
  }

  /// История поиска: список недавних запросов, тап — повторить поиск,
  /// плюс кнопка очистить. Раньше пункт был некликабельным.
  void _recentSearchesSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => Consumer(
        builder: (ctx, r, __) {
          final c = ctx.colors;
          final recent = r.watch(recentSearchesProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('История поиска',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      if (recent.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              r.read(recentSearchesProvider.notifier).clear(),
                          child: const Text('Очистить'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (recent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('Вы ещё ничего не искали.',
                          style: TextStyle(color: c.gray)),
                    )
                  else
                    for (final q in recent)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.history, color: c.gray),
                        title: Text(q),
                        trailing: Icon(Icons.north_west, size: 16, color: c.gray),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('${Routes.search}?q=${Uri.encodeComponent(q)}');
                        },
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _proUntilText(DateTime? until) {
    if (until == null) return 'Все возможности тарифа открыты.';
    final d = until.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return 'Действует до $dd.$mm.${d.year}. Все возможности открыты.';
  }

  void _notifyDialog(BuildContext context, WidgetRef ref) {
    final saved = ref.read(settingsProvider);
    final isPro = ref.read(myProfileProvider).valueOrNull?.isPro ?? false;
    bool enabled = saved.notifyEnabled;
    // Без тарифа ловим только заметные скидки, с тарифом — любые
    const options = [1, 5, 10, 20];
    const freeMin = 10;
    int threshold =
        isPro ? saved.notifyThreshold : max(saved.notifyThreshold, freeMin);

    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final c = ctx.colors;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Уведомления о снижении цены',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Присылать уведомления'),
                  value: enabled,
                  activeColor: c.orange,
                  onChanged: (v) => setSheet(() => enabled = v),
                ),
                const SizedBox(height: 8),
                Text('Минимальное снижение для уведомления',
                    style: TextStyle(fontSize: 13, color: c.gray)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final o in options)
                      ChoiceChip(
                        avatar: (!isPro && o < freeMin)
                            ? Icon(Icons.lock_outline, size: 16, color: c.gray)
                            : null,
                        label: Text('от $o%'),
                        selected: threshold == o,
                        onSelected: !enabled
                            ? null
                            : (_) {
                                if (!isPro && o < freeMin) {
                                  Navigator.pop(ctx);
                                  context.push(Routes.plans());
                                  return;
                                }
                                setSheet(() => threshold = o);
                              },
                      ),
                  ],
                ),
                if (!isPro) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Порог ниже $freeMin% — в тарифе КОМПЛЕКТ Про',
                    style: TextStyle(fontSize: 12, color: c.gray),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      // Сначала сохраняем на устройстве — это не может
                      // не сработать, выбор пользователя не теряется.
                      ref.read(settingsProvider.notifier).setNotifyPrefs(
                            enabled: enabled,
                            threshold: threshold,
                          );
                      // Затем пробуем записать в профиль. Если в базе ещё
                      // нет колонок, приложение продолжает работать.
                      try {
                        await ref
                            .read(authRepositoryProvider)
                            .updateNotifyPrefs(
                                enabled: enabled, threshold: threshold);
                        ref.invalidate(myProfileProvider);
                      } catch (_) {/* настройка осталась локальной */}
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _deleteAccountDialog(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      // Закрываем диалог его собственным контекстом (dialogCtx): контекст
      // экрана Профиля указывает на навигатор вкладки, и pop им закрывал
      // сам экран — из-за этого «Отмена» давала белый экран.
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
            'Профиль, избранное, подборки и отзывы будут удалены безвозвратно.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: context.colors.red),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await ref.read(authRepositoryProvider).deleteAccount();
              } catch (e) {
                final t = e.toString();
                messenger.showSnackBar(SnackBar(
                    content: Text(t.startsWith('Failure: ')
                        ? t.substring(9)
                        : 'Не удалось удалить аккаунт')));
              }
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _cityDialog(BuildContext context, WidgetRef ref) {
    const cities = ['Астана', 'Алматы', 'Шымкент', 'Караганда', 'Атырау'];
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final city in cities)
              ListTile(
                title: Text(city),
                trailing: ref.read(settingsProvider).city == city
                    ? Icon(Icons.check, color: context.colors.orange)
                    : null,
                onTap: () {
                  ref.read(settingsProvider.notifier).setCity(city);
                  // сохраняем город и в профиль пользователя (в фоне)
                  ref.read(authRepositoryProvider).updateCity(city);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuItemData {
  _MenuItemData(this.title, this.value, {this.icon, this.onTap, this.trailing});
  final String title;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
}

/// Заметная карточка входа в кабинет поставщика (как в макете).
class _CabinetCard extends StatelessWidget {
  const _CabinetCard({required this.isSupplier, required this.onTap});
  final bool isSupplier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.orangeSoft,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(Icons.storefront_rounded, color: c.orange, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        isSupplier ? 'Кабинет поставщика' : 'Стать поставщиком',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text('Управление товарами и запасами',
                        style: TextStyle(fontSize: 12, color: c.gray)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});
  final List<_MenuItemData> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++)
            InkWell(
              onTap: items[i].onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    top: i == 0
                        ? BorderSide.none
                        : BorderSide(color: c.line.withOpacity(0.6)),
                  ),
                ),
                child: Row(
                  children: [
                    if (items[i].icon != null) ...[
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.paper,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          border: Border.all(color: c.line),
                        ),
                        child: Icon(items[i].icon, size: 18, color: c.orange),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(items[i].title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    items[i].trailing ??
                        Text(items[i].value,
                            style: TextStyle(fontSize: 12, color: c.gray)),
                    if (items[i].trailing == null && items[i].onTap != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child:
                            Icon(Icons.chevron_right, color: c.faint, size: 20),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
