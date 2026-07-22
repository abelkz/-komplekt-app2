import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../catalog/presentation/widgets/product_thumb.dart';
import '../data/spec_export.dart';
import '../domain/collection.dart';
import 'collections_providers.dart';

/// Экран 7 — Подборки/проекты: позиции, количество, итог, экспорт.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                data: (list) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    for (final col in list) _CollectionBlock(collection: col),
                  ],
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
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewCollectionDialog(),
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

/// Переименование: то же поле ввода, но с текущим названием.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _ctrl.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Название подборки'),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(onPressed: _submit, child: const Text('Сохранить')),
        ],
      );
}

/// Отдельный виджет — чтобы контроллер поля корректно освобождался.
class _NewCollectionDialog extends StatefulWidget {
  const _NewCollectionDialog();

  @override
  State<_NewCollectionDialog> createState() => _NewCollectionDialogState();
}

class _NewCollectionDialogState extends State<_NewCollectionDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая подборка'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(hintText: 'Например: Кафе · Атырау'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _submit, child: const Text('Создать')),
      ],
    );
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
        Row(
          children: [
            Expanded(
              child: Text(collection.name,
                  style: AppTypography.unbounded(size: 18)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: c.orangeSoft,
                  borderRadius: BorderRadius.circular(999)),
              child: Text('${collection.items.length} поз.',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: c.orange)),
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
        const SizedBox(height: 12),

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
          for (final item in collection.items)
            _ItemRow(collectionId: collection.id, item: item),
          const SizedBox(height: 8),
          // Итог
          // Итог документа: жирная линейка, моно-подпись и крупная сумма
          Container(
            padding: const EdgeInsets.only(top: 18, bottom: 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.ink, width: 1.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text('ИТОГО ПО ЛУЧШИМ ЦЕНАМ',
                      style: AppTypography.sectionLabel(color: c.gray)),
                ),
                const SizedBox(width: 10),
                Text(Formatters.price(collection.total),
                    style: AppTypography.unbounded(size: 26, color: c.ink)),
              ],
            ),
          ),
          const SizedBox(height: 10),
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
                  onTap: () => _export(
                      context, (o) => SpecExport.exportPdf(collection, shareOrigin: o)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  /// Переименование подборки.
  Future<void> _renameDialog(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: collection.name),
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
      final sum = (best?.price ?? 0) * i.qty;
      return '· $name — ${Formatters.number(i.qty)} ${p?.unit ?? ''} × '
          '${Formatters.price(best?.price ?? 0)} = ${Formatters.price(sum)}';
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

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => context.push(Routes.product(p.id)),
            child: Row(
              children: [
                ProductThumb(product: p, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                        '${best?.supplierName ?? ''} · ${Formatters.price(best?.price ?? 0)}/${p.unit}',
                        style: TextStyle(fontSize: 11, color: c.faint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Stepper(
                qty: item.qty,
                unit: p.unit,
                onMinus: () => notifier.setQty(
                    collectionId, p.id, item.qty - 1),
                onPlus: () => notifier.setQty(
                    collectionId, p.id, item.qty + 1),
              ),
              const Spacer(),
              Text(Formatters.price(item.sum),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
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
  });
  final double qty;
  final String unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('${Formatters.number(qty)} $unit',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
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
