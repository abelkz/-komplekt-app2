import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/build_info.dart';
import '../../../core/providers/data_refresh.dart';
import '../../../core/providers/providers.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/sign_in_required.dart';
import '../../admin/presentation/admin_providers.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../collections/presentation/collections_providers.dart';
import '../../favorites/presentation/favorites_providers.dart';

/// Экран 8 — Профиль пользователя.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;

    // Гость: аккаунта нет, показывать нечего кроме предложения войти и
    // тех настроек, что живут на устройстве (город и тема).
    if (!ref.watch(isSignedInProvider)) {
      return _guestView(context, ref);
    }

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

    return Scaffold(
      body: SafeArea(
        // Потянуть вниз — перечитать профиль: так виден только что
        // включённый тариф, без перезапуска приложения
        child: RefreshIndicator(
          onRefresh: () async => refreshAppData(ref),
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Row(
              children: [
                Text('Профиль',
                    style: AppTypography.headlineSm(color: c.ink)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.field,
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                  ),
                  child: Text(_roleLabel(profile.valueOrNull, isAdmin),
                      style: AppTypography.data(color: c.accent)),
                ),
                const Spacer(),
                _SquareAction(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Уведомления',
                  onTap: () => context.push(Routes.notifications),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Карточка пользователя: монограмма, контакт, роль и город,
            // а под ними полоса показателей — всё, что приложение о человеке
            // действительно знает.
            _IdentityCard(
              name: name,
              phone: profile.valueOrNull?.phone,
              role: _roleLine(profile.valueOrNull, isAdmin, settings.city),
              city: settings.city,
              onCity: () => _cityDialog(context, ref),
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

  /// Профиль гостя: предложение войти плюс настройки, которые хранятся на
  /// устройстве и работают без аккаунта — город и тема.
  Widget _guestView(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Text('Профиль', style: AppTypography.unbounded()),
            const SizedBox(height: 14),
            const SignInRequired(
              icon: Icons.person_outline_rounded,
              title: 'Вы не вошли',
              subtitle: 'Каталог и цены доступны без регистрации. Аккаунт '
                  'нужен для избранного, подборок и кабинета поставщика.',
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text('НАСТРОЙКИ',
                  style: AppTypography.sectionLabel(color: c.faint)),
            ),
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
            ]),
            const SizedBox(height: 26),
            Center(
              child: Text(BuildInfo.label,
                  style: TextStyle(fontSize: 11, color: c.faint)),
            ),
          ],
        ),
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

/// Короткая метка роли для чипа у заголовка.
String _roleLabel(AppUser? u, bool isAdmin) {
  if (isAdmin) return 'АДМИН';
  if (u?.isSupplier == true) return 'ПОСТАВЩИК';
  return 'ПОКУПАТЕЛЬ';
}

/// Строка под именем: кто человек и в каком городе смотрит каталог.
/// В макете здесь «Инженер технадзора · Астана» — должности приложение не
/// хранит, поэтому пишем то, что знаем на самом деле: роль и город.
String _roleLine(AppUser? u, bool isAdmin, String city) {
  final role = isAdmin
      ? 'Администратор'
      : (u?.isSupplier == true ? 'Поставщик' : 'Покупатель');
  return '$role · $city';
}

class _MenuItemData {
  _MenuItemData(
    this.title,
    this.value, {
    this.subtitle,
    this.icon,
    this.onTap,
    this.trailing,
  });
  final String title;
  final String value;

  /// Пояснение под названием пункта: что именно он делает.
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
}

/// Квадратная кнопка-действие в шапке экрана.
class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: c.gray),
          ),
        ),
      ),
    );
  }
}

/// Фото профиля: показ, замена и удаление.
///
/// Снимок — единственное на этом экране, что человек про себя задаёт сам,
/// поэтому кнопки прячем под сам аватар: отдельная кнопка «загрузить фото»
/// заняла бы строку ради действия, которое делают один раз.
class _AvatarPicker extends ConsumerStatefulWidget {
  const _AvatarPicker({required this.name});

  final String name;

  @override
  ConsumerState<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends ConsumerState<_AvatarPicker> {
  bool _busy = false;

  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Аватарку показываем максимум 56 точками, но в галерее у человека
        // снимки по 4 МБ. Ужимаем до загрузки: на мобильном интернете
        // разница между 4 МБ и 100 КБ — это разница между «сразу» и «никогда».
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final ext = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final url =
          await ref.read(storageRepositoryProvider).uploadAvatar(bytes, ext: ext);
      await ref.read(authRepositoryProvider).updateAvatar(url);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final t = e.toString();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content:
                Text(t.startsWith('Failure: ') ? t.substring(9) : 'Не вышло')));
    }
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).updateAvatar(null);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      final t = e.toString();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content:
                Text(t.startsWith('Failure: ') ? t.substring(9) : 'Не вышло')));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = ref.watch(myProfileProvider).valueOrNull?.avatarUrl;
    final hasPhoto = url != null && url.isNotEmpty;

    return GestureDetector(
      onTap: _busy ? null : _pick,
      // Долгое нажатие снимает фото. Отдельная корзина рядом с аватаркой
      // мозолила бы глаза ради действия, которое делают редко.
      onLongPress: _busy || !hasPhoto ? null : _remove,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Avatar(name: widget.name, url: url, size: 56),
          if (_busy)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
            )
          else if (!hasPhoto)
            // Значок камеры только когда фото нет: иначе он закрывал бы
            // сам снимок, ради которого всё и делалось.
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: c.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                ),
                child: Icon(Icons.photo_camera_outlined,
                    size: 11, color: c.gray),
              ),
            ),
        ],
      ),
    );
  }
}

/// Карточка пользователя: монограмма, имя, телефон, роль и выбор города.
class _IdentityCard extends ConsumerWidget {
  const _IdentityCard({
    required this.name,
    required this.phone,
    required this.role,
    required this.city,
    required this.onCity,
  });

  final String name;
  final String? phone;
  final String role;
  final String city;
  final VoidCallback onCity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cols = ref.watch(collectionsProvider).valueOrNull ?? const [];

    // Показатели считаем по подборкам — это единственное, что приложение
    // про человека действительно знает. Выдуманных «14 баз» здесь нет.
    final specs = cols.length;
    var saved = 0.0;
    final suppliers = <String>{};
    for (final col in cols) {
      for (final item in col.items) {
        final p = item.product;
        if (p == null) continue;
        final mn = p.minPrice, mx = p.maxPrice;
        if (mn != null && mx != null && mx > mn) saved += (mx - mn) * item.qty;
        final sid = p.bestOffer?.supplierId;
        if (sid != null) suppliers.add(sid);
      }
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Форма прямоугольная со скруглением, а не круг: круглые
                // аватары — язык соцсетей, здесь учётная запись.
                _AvatarPicker(name: name),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headlineSm(color: c.ink)),
                      if (phone != null && phone!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(phone!,
                            style: AppTypography.data(color: c.faint)),
                      ],
                      const SizedBox(height: 4),
                      Text(role.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.sectionLabel(color: c.gray)
                              .copyWith(fontSize: 10)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: c.field,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onCity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 15, color: c.accent),
                          const SizedBox(width: 4),
                          Text(city,
                              style: AppTypography.data(color: c.ink)),
                          Icon(Icons.expand_more_rounded,
                              size: 14, color: c.faint),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Полоса показателей на подложке потемнее — во всю ширину карточки.
          Container(
            decoration: BoxDecoration(
              color: c.paper,
              border: Border(top: BorderSide(color: c.line)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                _Stat(label: 'СМЕТЫ', value: '$specs'),
                _Stat(
                  label: 'СЭКОНОМЛЕНО',
                  value: Formatters.priceOr(saved, fallback: '—'),
                  accent: true,
                ),
                _Stat(label: 'ПОСТАВЩИКОВ', value: '${suppliers.length}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.accent = false});
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sectionLabel(color: c.faint)
                  .copyWith(fontSize: 9)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.priceMd(color: accent ? c.accent : c.ink)),
        ],
      ),
    );
  }
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(items[i].title,
                              style: AppTypography.bodyMd(color: c.ink)),
                          // Пояснение под названием: в списке настроек
                          // человек не должен гадать, что сделает пункт.
                          if (items[i].subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(items[i].subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySm(color: c.faint)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    items[i].trailing ??
                        Text(items[i].value,
                            style: AppTypography.data(color: c.gray)),
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
