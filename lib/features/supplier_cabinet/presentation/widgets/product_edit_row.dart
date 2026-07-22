import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../catalog/domain/product.dart';
import '../../../catalog/presentation/widgets/product_thumb.dart';
import '../../data/supplier_cabinet_repository.dart';
import '../supplier_cabinet_providers.dart';

/// Строка редактирования товара в кабинете: цена, наличие, статистика.
class ProductEditRow extends ConsumerStatefulWidget {
  const ProductEditRow({
    super.key,
    required this.product,
    required this.supplierId,
    this.stat,
  });

  final Product product;
  final String supplierId;
  final ProductStat? stat;

  @override
  ConsumerState<ProductEditRow> createState() => _ProductEditRowState();
}

class _ProductEditRowState extends ConsumerState<ProductEditRow> {
  late final TextEditingController _price;
  late bool _inStock;

  String? get _offerId =>
      widget.product.offers.isNotEmpty ? widget.product.offers.first.id : null;

  @override
  void initState() {
    super.initState();
    final offer =
        widget.product.offers.isNotEmpty ? widget.product.offers.first : null;
    _price = TextEditingController(
        text: offer != null ? offer.price.toStringAsFixed(0) : '');
    _inStock = offer?.inStock ?? true;
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  /// Цена или наличие отличаются от того, что сейчас в базе
  bool get _dirty {
    final offer =
        widget.product.offers.isNotEmpty ? widget.product.offers.first : null;
    final typed = double.tryParse(_price.text.replaceAll(',', '.'));
    if (offer == null) return typed != null && typed > 0;
    return typed != offer.price || _inStock != offer.inStock;
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    if (price == null || price <= 0) {
      _snack('Цена должна быть числом больше нуля');
      return;
    }
    final ok = await ref.read(cabinetControllerProvider.notifier).saveOffer(
          offerId: _offerId,
          productId: widget.product.id,
          supplierId: widget.supplierId,
          price: price,
          inStock: _inStock,
        );
    if (ok) {
      _snack('Цена обновлена ✓');
      return;
    }
    // Показываем настоящий текст ошибки от базы, а не общую фразу
    final e = ref.read(cabinetControllerProvider).error;
    final t = e?.toString() ?? '';
    _snack(t.startsWith('Failure: ') ? t.substring(9) : 'Не удалось сохранить');
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: const Text('Товар и его цена исчезнут из каталога.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (confirm == true) {
      await ref
          .read(cabinetControllerProvider.notifier)
          .deleteProduct(widget.product.id);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.product;

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      [
                        if (p.sku.isNotEmpty) 'арт. ${p.sku}',
                        'ед. ${p.unit}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11, color: c.faint),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: c.red, size: 20),
                onPressed: _delete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  // перерисовываем строку, чтобы кнопка сохранения ожила
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Цена, ₸',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Наличие
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _inStock = !_inStock),
                  child: Row(
                    children: [
                      Switch(
                        value: _inStock,
                        activeColor: c.green,
                        onChanged: (v) => setState(() => _inStock = v),
                      ),
                      Flexible(
                        child: Text(_inStock ? 'В наличии' : 'Под заказ',
                            style: TextStyle(fontSize: 12, color: c.gray)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Явная кнопка вместо маленькой галочки: пока ничего не меняли —
          // она приглушена, после правки цены становится активной.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: _dirty ? c.accent : c.field,
                foregroundColor: _dirty ? AppColors.brandInk : c.gray,
              ),
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(_dirty ? 'Обновить цену' : 'Цена сохранена'),
              onPressed: _dirty ? _save : null,
            ),
          ),
          if (widget.stat != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 14, color: c.faint),
                  const SizedBox(width: 4),
                  Text('${widget.stat!.views} просмотров',
                      style: TextStyle(fontSize: 11, color: c.faint)),
                  const SizedBox(width: 12),
                  Icon(Icons.call_outlined, size: 14, color: c.faint),
                  const SizedBox(width: 4),
                  Text('${widget.stat!.contacts} контактов',
                      style: TextStyle(fontSize: 11, color: c.faint)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
