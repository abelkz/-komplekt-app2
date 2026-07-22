import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/collection.dart';
import '../collections_providers.dart';

/// Лист выбора подборки: в какую именно положить товар.
/// Открывается с карточки товара, когда подборок больше одной.
Future<void> showCollectionPicker(
  BuildContext context,
  WidgetRef ref,
  String productId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CollectionPicker(productId: productId),
  );
}

class _CollectionPicker extends ConsumerWidget {
  const _CollectionPicker({required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final list = ref.watch(collectionsProvider).valueOrNull ?? const <Collection>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('В какую подборку?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Нажмите, чтобы добавить или убрать товар',
                style: TextStyle(fontSize: 12, color: c.gray)),
            const SizedBox(height: 14),

            // Список подборок с отметками
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final col = list[i];
                  final inside =
                      col.items.any((it) => it.productId == productId);
                  return _Row(
                    title: col.name,
                    subtitle: '${col.items.length} поз.',
                    checked: inside,
                    onTap: () => _toggle(context, ref, col, inside),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.ink,
                  side: BorderSide(color: c.line),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Новая подборка'),
                onPressed: () => _createAndAdd(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, Collection col, bool inside) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(collectionsProvider.notifier);
    try {
      if (inside) {
        await notifier.removeItem(col.id, productId);
        messenger.showSnackBar(
            SnackBar(content: Text('Убрано из «${col.name}»')));
      } else {
        await notifier.addTo(col.id, productId);
        messenger.showSnackBar(
            SnackBar(content: Text('Добавлено в «${col.name}»')));
      }
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  Future<void> _createAndAdd(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(collectionsProvider.notifier).createWith(name, productId);
      messenger.showSnackBar(SnackBar(content: Text('Добавлено в «$name»')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  String _msg(Object e) {
    final t = e.toString();
    return t.startsWith('Failure: ') ? t.substring(9) : 'Не получилось';
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.checked,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: checked ? c.accent : c.line),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            Icon(checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20, color: checked ? c.accent : c.gray),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Text(subtitle, style: TextStyle(fontSize: 11, color: c.gray)),
          ],
        ),
      ),
    );
  }
}

/// Ввод названия новой подборки.
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _ctrl.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Новая подборка'),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration:
              const InputDecoration(hintText: 'Например: Кафе · Атырау'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(onPressed: _submit, child: const Text('Создать')),
        ],
      );
}
