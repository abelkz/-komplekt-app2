import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/data_refresh.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/sign_in_required.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/domain/offer.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/widgets/product_thumb.dart';
import '../data/spec_export.dart';
import '../domain/collection.dart';
import 'collections_providers.dart';
import 'widgets/qty_calculator_page.dart';
import 'widgets/text_entry_page.dart';

/// Экран 7 — Подборки/проекты: позиции, количество, итог, экспорт.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Подборки привязаны к аккаунту — гостю предлагаем войти.
    if (!ref.watch(isSignedInProvider)) {
      return const Scaffold(
        body: SafeArea(
          child: SignInRequired(
            icon: Icons.layers_outlined,
            title: 'Подборки — после входа',
            subtitle: 'Войдите, чтобы собирать материалы по объектам и '
                'выгружать смету в Excel или PDF.',
          ),
        ),
      );
    }

    final collections = ref.watch(collectionsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                children: [
                  Text('Подборки', style: AppTypography.unbounded()),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () => _createDialog(context, ref),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AsyncValueView<List<Collection>>(
                value: collections,
                onRetry: () => ref.invalidate(collectionsProvider),
                isEmpty: (d) => d.isEmpty,
                empty: const EmptyState(
                  title: 'Подборок пока нет',
                  subtitle: 'Нажмите + и создайте первую подборку.',
                  icon: Icons.layers_outlined,
                ),
                // Показываем и пустые подборки — иначе после создания
                // на экране ничего не появляется и кажется, что зависло.
                data: (list) => RefreshIndicator(
                  onRefresh: () async => refreshAppData(ref),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      for (final col in list) _CollectionBlock(collection: col),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Диалог «Новая подборка».
  /// Создание ждём и ошибку показываем: раньше исключение из create()
  /// никто не ловил — на вебе это роняло кадр и экран оставался пустым.
  Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await promptText(
      context,
      title: 'Новая подборка',
      label: 'Название',
      hint: 'Например: Кафе · Атырау',
      action: 'Создать',
    );
    if (name == null || name.isEmpty) return;

    try {
      await ref.read(collectionsProvider.notifier).create(name);
      messenger.showSnackBar(SnackBar(content: Text('Подборка «$name» создана')));
    } catch (e) {
      final t = e.toString();
      messenger.showSnackBar(SnackBar(
        content: Text(t.startsWith('Failure: ')
            ? t.substring(9)
            : 'Не удалось создать подборку'),
      ));
    }
  }
}

class _CollectionBlock extends ConsumerWidget {
  const _CollectionBlock({required this.collection});
  final Collection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Шапка сметы: название, под ним служебная строка с числом позиций.
        // Число вынесено из пилюли в строку метаданных — в макете это
        // подпись документа, а не ярлык.
        Row(
          children: [
            Icon(Icons.edit_note_rounded, size: 22, color: c.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                collection.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.headlineMd(color: c.ink),
              ),
            ),
            // Переименовать / удалить подборку
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: c.gray),
              tooltip: 'Действия с подборкой',
              onSelected: (v) => v == 'rename'
                  ? _renameDialog(context, ref)
                  : _deleteDialog(context, ref),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                PopupMenuItem(value: 'delete', child: Text('Удалить подборку')),
              ],
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30, bottom: 12),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: c.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                '${collection.items.length} '
                '${_positionsPlural(collection.items.length)}',
                style: AppTypography.data(color: c.gray),
              ),
              Text('   |   ', style: AppTypography.data(color: c.line)),
              Text('по минимальным ценам',
                  style: AppTypography.data(color: c.faint)),
            ],
          ),
        ),

        // Пустая подборка: подсказка вместо итога и кнопок экспорта
        if (collection.items.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Text(
              'Пока пусто. Найдите товар и добавьте его в эту подборку.',
              style: TextStyle(fontSize: 13, color: c.gray),
            ),
          ),
          const SizedBox(height: 24),
        ],

        if (collection.items.isNotEmpty) ...[
          // Итог идёт ПЕРЕД списком, как в макете: смета открывается с
          // ответа на главный вопрос — сколько всего. Раньше до суммы надо
          // было пролистать все позиции.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ИТОГО ПО СМЕТЕ',
                    style: AppTypography.sectionLabel(color: c.faint)),
                const SizedBox(height: 6),
                Text(Formatters.priceOr(collection.total, fallback: '—'),
                    style: AppTypography.priceLg(color: c.accent)
                        .copyWith(fontSize: 30, height: 36 / 30)),
                if (_supplierCount(collection) > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.verified_outlined, size: 14, color: c.accent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'по минимальным ценам '
                          '${_supplierCount(collection)} '
                          '${_supplierPlural(_supplierCount(collection))}',
                          style: AppTypography.bodySm(color: c.gray),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Шапка таблицы: метка раздела и подписи колонок — как в смете
          // на бумаге. Без них столбец справа читается как набор чисел.
          Row(
            children: [
              Expanded(
                child: Text('СПЕЦИФИКАЦИЯ МАТЕРИАЛОВ',
                    style: AppTypography.sectionLabel(color: c.gray)),
              ),
              Text(
                '${collection.items.length} '
                '${_positionsPlural(collection.items.length)}',
                style: AppTypography.data(color: c.faint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Text('МАТЕРИАЛ / ЕД.',
                      style: AppTypography.sectionLabel(color: c.faint)
                          .copyWith(fontSize: 10)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('КОЛ-ВО',
                      textAlign: TextAlign.center,
                      style: AppTypography.sectionLabel(color: c.faint)
                          .copyWith(fontSize: 10)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('СУММА',
                      textAlign: TextAlign.right,
                      style: AppTypography.sectionLabel(color: c.faint)
                          .copyWith(fontSize: 10)),
                ),
              ],
            ),
          ),
          Container(height: 1, color: c.line),
          const SizedBox(height: 10),

          for (final item in collection.items)
            _ItemRow(collectionId: collection.id, item: item),
          const SizedBox(height: 4),

          // Готовность к комплектации: сколько позиций можно забрать сразу.
          // Считается по in_stock у предложений — никаких выдуманных
          // процентов «сверки со складами».
          _Readiness(collection: collection),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ExportButton(
                  icon: Icons.content_copy,
                  label: 'Скопировать',
                  onTap: () => _copySpec(context, collection),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ExportButton(
                  icon: Icons.grid_on,
                  label: 'Excel',
                  onTap: () => _export(
                      context, (o) => SpecExport.exportExcel(collection, shareOrigin: o)),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ExportButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  // По тарифу спецификация уходит заказчику под реквизитами
                  // самого дизайнера, без тарифа — под нашими
                  onTap: () => _export(
                      context,
                      (o) => SpecExport.exportPdf(collection,
                          shareOrigin: o, brand: _brandOf(ref))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Заявка поставщикам: открывает чат с готовым текстом запроса
          _SendToSuppliersButton(
            onTap: () => _sendToSuppliers(context, collection),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Future<void> _sendToSuppliers(BuildContext context, Collection col) async {
    if (col.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('В комплекте нет позиций')));
      return;
    }
    final origin = _shareOrigin(context);
    try {
      await SpecExport.shareForSuppliers(col, shareOrigin: origin);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_err(e, 'Не удалось открыть отправку'))));
      }
    }
  }

  /// Реквизиты для подписи PDF — только у активного тарифа Про.
  static SpecBrand? _brandOf(WidgetRef ref) {
    final me = ref.read(myProfileProvider).valueOrNull;
    if (me == null || !me.isPro) return null;
    final company = me.company.isNotEmpty ? me.company : me.fullName;
    if (company.isEmpty) return null;
    return SpecBrand(company: company, phone: me.phone);
  }

  /// Переименование подборки.
  Future<void> _renameDialog(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await promptText(
      context,
      title: 'Переименовать',
      label: 'Название',
      initial: collection.name,
      action: 'Сохранить',
    );
    if (name == null || name.isEmpty || name == collection.name) return;
    try {
      await ref.read(collectionsProvider.notifier).rename(collection.id, name);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_err(e, 'Не удалось переименовать'))));
    }
  }

  /// Удаление подборки — с подтверждением, действие необратимое.
  Future<void> _deleteDialog(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить «${collection.name}»?'),
        content: const Text(
            'Подборка и все её позиции будут удалены. Отменить нельзя.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(collectionsProvider.notifier).remove(collection.id);
      messenger.showSnackBar(
          SnackBar(content: Text('Подборка «${collection.name}» удалена')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(_err(e, 'Не удалось удалить'))));
    }
  }

  String _err(Object e, String fallback) {
    final t = e.toString();
    return t.startsWith('Failure: ') ? t.substring(9) : fallback;
  }

  void _copySpec(BuildContext context, Collection col) {
    final lines = col.items.map((i) {
      final p = i.product;
      final best = p?.bestOffer;
      final name = p?.name ?? '';
      final qty = '${Formatters.number(i.qty)} ${p?.unit ?? ''}'.trim();
      if (best == null) return '· $name — $qty · ${Formatters.priceUnset}';
      return '· $name — $qty × ${Formatters.price(best.price)} '
          '= ${Formatters.price(best.price * i.qty)}';
    }).join('\n');
    final text = 'Спецификация «${col.name}»\n\n$lines\n\n'
        'Итого: ${Formatters.price(col.total)}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Спецификация скопирована')));
  }

  /// Прямоугольник кнопок экспорта в глобальных координатах — нужен iPad'у,
  /// чтобы привязать поповер «Поделиться». На iPhone/Android не используется.
  Rect? _shareOrigin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _export(
      BuildContext context, Future<void> Function(Rect? origin) action) async {
    final messenger = ScaffoldMessenger.of(context);
    final origin = _shareOrigin(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Готовлю файл…')));
    try {
      await action(origin);
    } catch (e) {
      final msg = e.toString().startsWith('Failure: ')
          ? e.toString().substring(9)
          : 'Не удалось сформировать файл';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

/// Сколько разных поставщиков стоит за итогом.
///
/// Для сметы это не менее важно, чем сумма: «по минимальным ценам четырёх
/// поставщиков» значит, что за материалами придётся объехать четыре адреса.
/// Прораб должен видеть это до того, как покажет смету заказчику.
int _supplierCount(Collection collection) => collection.items
    .map((i) => i.product?.bestOffer?.supplierId)
    .whereType<String>()
    .toSet()
    .length;

/// «1 поставщика», «2 поставщиков» — вся фраза стоит в родительном падеже,
/// поэтому множественное число одно на все числа, кроме единицы.
String _supplierPlural(int n) =>
    (n % 10 == 1 && n % 100 != 11) ? 'поставщика' : 'поставщиков';

/// Готовность сметы к комплектации: доля позиций, которые есть в наличии
/// хотя бы у одного поставщика.
///
/// Это честный аналог «сверки со складами» из макета: остатков по складам
/// в базе нет, а вот признак «в наличии» у предложения есть. Прорабу важно
/// ровно одно — можно ли ехать забирать всё разом или часть придётся ждать.
class _Readiness extends StatelessWidget {
  const _Readiness({required this.collection});
  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items =
        collection.items.where((i) => i.product != null).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final ready = items
        .where((i) => i.product!.offers.any((o) => o.inStock))
        .length;
    final percent = (ready / items.length * 100).round();
    final waiting = items.length - ready;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 18, color: c.gray),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Готовность к комплектации',
                    style: AppTypography.titleMd(color: c.ink)),
              ),
              Text('$percent %',
                  style: AppTypography.priceMd(
                      color: percent == 100 ? c.green : c.ink)),
            ],
          ),
          const SizedBox(height: 10),
          // Полоса заполнения — она же единственный график на экране:
          // доля читается быстрее, чем число.
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ready / items.length,
              minHeight: 4,
              backgroundColor: c.field,
              valueColor:
                  AlwaysStoppedAnimation(percent == 100 ? c.green : c.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            waiting == 0
                ? 'Все позиции есть в наличии — можно забирать разом.'
                : '$ready из ${items.length} в наличии, '
                    '$waiting ${_positionsPlural(waiting)} под заказ.',
            style: AppTypography.bodySm(color: c.gray),
          ),
        ],
      ),
    );
  }
}

/// «9 позиций», «1 позиция», «2 позиции».
String _positionsPlural(int n) {
  final m = n % 10, h = n % 100;
  if (m == 1 && h != 11) return 'позиция';
  if (m >= 2 && m <= 4 && (h < 10 || h >= 20)) return 'позиции';
  return 'позиций';
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({required this.collectionId, required this.item});
  final String collectionId;
  final CollectionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final p = item.product;
    if (p == null) return const SizedBox.shrink();
    final best = p.bestOffer;
    final notifier = ref.read(collectionsProvider.notifier);

    // Смахивание влево удаляет позицию из подборки. Действие обратимое —
    // в снекбаре есть «Вернуть», поэтому подтверждение не спрашиваем.
    return Dismissible(
      key: ValueKey('item-$collectionId-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.only(right: 22),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: c.red,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
      ),
      onDismissed: (_) => _remove(context, ref, notifier),
      child: _card(context, c, ref, p, best, notifier),
    );
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, CollectionsNotifier notifier) async {
    final messenger = ScaffoldMessenger.of(context);
    final qty = item.qty;
    try {
      await notifier.removeItem(collectionId, item.productId);
      messenger.showSnackBar(SnackBar(
        content: Text('${item.product?.name ?? 'Позиция'} убрана'),
        action: SnackBarAction(
          label: 'Вернуть',
          onPressed: () => notifier
              .addTo(collectionId, item.productId)
              .then((_) => notifier.setQty(collectionId, item.productId, qty))
              .catchError((_) {}),
        ),
      ));
    } catch (e) {
      final t = e.toString();
      messenger.showSnackBar(SnackBar(
          content: Text(t.startsWith('Failure: ')
              ? t.substring(9)
              : 'Не удалось убрать позицию')));
    }
  }

  /// Ввод количества — набирать 40 штук плюсиком невозможно.
  ///
  /// Открываем не голое поле, а расчёт: то же ручное число вводится в первую
  /// строку, но рядом сразу видно запас на подрезку и округление до целых
  /// упаковок. Без этого смета занижена ровно на то, что доплачивают потом.
  Future<void> _editQty(
      BuildContext context, CollectionsNotifier notifier, Product p) async {
    final value = await showQtyCalculator(context, p, initial: item.qty);
    if (value == null || value <= 0) return;
    try {
      await notifier.setQty(collectionId, p.id, value);
    } catch (_) {/* ошибку покажет сам экран при перезагрузке */}
  }

  Widget _card(BuildContext context, AppColors c, WidgetRef ref, Product p,
      Offer? best, CollectionsNotifier notifier) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      // Строка сметы в три колонки — те же доли, что у подписей выше
      // (6 / 3 / 3). Раньше количество и сумма стояли отдельной строкой под
      // названием, и колонка сумм не складывалась.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 6,
            child: InkWell(
              onTap: () => context.push(Routes.product(p.id)),
              child: Row(
                children: [
                  ProductThumb(product: p, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMd(color: c.ink)),
                        const SizedBox(height: 2),
                        Text(
                          // Нет предложений — вместо «0 ₸» честная подпись
                          best == null
                              ? Formatters.priceUnset
                              : '${Formatters.price(best.price)}/${p.unit} · '
                                  '${best.supplierName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySm(color: c.faint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: _Stepper(
                qty: item.qty,
                unit: p.unit,
                onMinus: () =>
                    notifier.setQty(collectionId, p.id, item.qty - 1),
                onPlus: () => notifier.setQty(collectionId, p.id, item.qty + 1),
                // по нажатию на число — ввод вручную: набирать 40 штук
                // плюсиком невозможно
                onEdit: () => _editQty(context, notifier, p),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              Formatters.priceOr(item.sum, fallback: '—'),
              textAlign: TextAlign.right,
              // Моноширинным с табличными цифрами: суммы позиций
              // выстраиваются в колонку и читаются как смета.
              style: AppTypography.priceMd(color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.qty,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    this.onEdit,
  });
  final double qty;
  final String unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  /// Нажатие по самому числу — ввод количества с клавиатуры
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: c.field, borderRadius: BorderRadius.circular(AppRadii.sm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(c, Icons.remove, onMinus),
          InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('${Formatters.number(qty)} $unit',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      // подчёркиванием намекаем, что число можно нажать
                      decoration:
                          onEdit == null ? null : TextDecoration.underline,
                      decorationColor: c.gray,
                      decorationStyle: TextDecorationStyle.dotted)),
            ),
          ),
          _btn(c, Icons.add, onPlus),
        ],
      ),
    );
  }

  Widget _btn(AppColors c, IconData icon, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              color: c.card, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 16, color: c.ink),
        ),
      );
}

class _ExportButton extends StatelessWidget {
  const _ExportButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          children: [
            Icon(icon, color: c.orange, size: 20),
            const SizedBox(height: 6),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Крупная тёмная кнопка «Отправить заявку поставщикам».
class _SendToSuppliersButton extends StatelessWidget {
  const _SendToSuppliersButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Отправить заявку поставщикам',
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('ответ с предложением — в чат',
                      style: TextStyle(color: c.gray, fontSize: 12)),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.orange,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: const Icon(Icons.arrow_forward,
                  color: AppColors.brandInk, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
