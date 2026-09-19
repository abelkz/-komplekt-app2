import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../catalog/domain/offer.dart';
import '../../../catalog/domain/product.dart';
import '../../../catalog/presentation/widgets/product_thumb.dart';
import '../../data/supplier_cabinet_repository.dart';
import '../supplier_cabinet_providers.dart';
import 'add_product_sheet.dart';
import 'promote_sheet.dart';

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
  late final TextEditingController _stock;
  late final TextEditingController _lead;
  late bool _inStock;

  String? get _offerId =>
      widget.product.offers.isNotEmpty ? widget.product.offers.first.id : null;

  Offer? get _offer =>
      widget.product.offers.isNotEmpty ? widget.product.offers.first : null;

  @override
  void initState() {
    super.initState();
    final offer = _offer;
    _price = TextEditingController(
        text: offer != null ? offer.price.toStringAsFixed(0) : '');
    _stock = TextEditingController(text: _num(offer?.stockQty));
    _lead = TextEditingController(text: offer?.leadTimeDays?.toString() ?? '');
    _inStock = offer?.inStock ?? true;
  }

  /// Остаток показываем без хвоста «.0»: 48 м², а не 48.0 м².
  static String _num(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  @override
  void dispose() {
    for (final c in [_price, _stock, _lead]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _typedStock =>
      double.tryParse(_stock.text.trim().replaceAll(',', '.'));

  int? get _typedLead => int.tryParse(_lead.text.trim());

  /// Цена, наличие, остаток или срок отличаются от того, что сейчас в базе
  bool get _dirty {
    final offer = _offer;
    final typed = double.tryParse(_price.text.replaceAll(',', '.'));
    if (offer == null) return typed != null && typed > 0;
    return typed != offer.price ||
        _inStock != offer.inStock ||
        _typedStock != offer.stockQty ||
        _typedLead != offer.leadTimeDays;
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    if (price == null || price <= 0) {
      _snack('Цена должна быть числом больше нуля');
      return;
    }
    // Пустое поле — это «не знаю», и так оно и уедет в базу (null).
    // А вот мусор вместо числа молча превращать в «не знаю» нельзя:
    // по остатку и сроку считают закупку.
    if (_stock.text.trim().isNotEmpty && _typedStock == null) {
      _snack('Остаток должен быть числом');
      return;
    }
    if (_lead.text.trim().isNotEmpty && _typedLead == null) {
      _snack('Срок поставки — целое число дней');
      return;
    }
    final ok = await ref.read(cabinetControllerProvider.notifier).saveOffer(
          offerId: _offerId,
          productId: widget.product.id,
          supplierId: widget.supplierId,
          price: price,
          inStock: _inStock,
          stockQty: _typedStock,
          leadTimeDays: _typedLead,
        );
    if (ok) {
      _snack('Сохранено ✓');
      return;
    }
    // Показываем настоящий текст ошибки от базы, а не общую фразу
    final e = ref.read(cabinetControllerProvider).error;
    final t = e?.toString() ?? '';
    _snack(t.startsWith('Failure: ') ? t.substring(9) : 'Не удалось сохранить');
  }

  bool get _promoted =>
      widget.product.offers.isNotEmpty && widget.product.offers.first.isPromoted;

  String _promotedUntilText() {
    final until = widget.product.offers.first.promotedUntil;
    if (until == null) return '';
    return '${until.day.toString().padLeft(2, '0')}.'
        '${until.month.toString().padLeft(2, '0')}';
  }

  void _promote() {
    final id = _offerId;
    if (id == null) {
      _snack('Сначала сохраните цену');
      return;
    }
    // Лист сам разберётся: бесплатная норма Pro или купленный Буст
    showPromoteSheet(context, id);
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
              // правка карточки: название, категория, фото, единица
              IconButton(
                tooltip: 'Изменить товар',
                icon: Icon(Icons.edit_outlined, color: c.gray, size: 20),
                onPressed: () => showEditProductSheet(
                    context, widget.supplierId, widget.product),
              ),
              IconButton(
                tooltip: 'Удалить товар',
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
          // Остаток и срок поставки (миграция 0029). Пустое поле — «не знаю»:
          // в карточке товара тогда просто ничего не обещаем покупателю.
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: _stock,
                  label: 'Остаток, ${p.unit}',
                  decimal: true,
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  controller: _lead,
                  label: 'Срок, дней',
                  hint: '0 — со склада',
                  onChanged: () => setState(() {}),
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
              label: Text(_dirty ? 'Сохранить' : 'Всё сохранено'),
              onPressed: _dirty ? _save : null,
            ),
          ),
          // Продвижение: поднимает товар в топ списков и поиска.
          // На шкалу цен внутри карточки не влияет — там только цена.
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _promoted
                ? Row(
                    children: [
                      Icon(Icons.trending_up, size: 14, color: c.accent),
                      const SizedBox(width: 5),
                      Text(
                        'В топе до ${_promotedUntilText()}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: c.accent),
                      ),
                    ],
                  )
                : InkWell(
                    onTap: _promote,
                    child: Row(
                      children: [
                        Icon(Icons.trending_up, size: 14, color: c.gray),
                        const SizedBox(width: 5),
                        Text('Поднять в топ на неделю',
                            style: TextStyle(
                                fontSize: 11,
                                color: c.gray,
                                decoration: TextDecoration.underline,
                                decorationStyle: TextDecorationStyle.dotted)),
                      ],
                    ),
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

/// Компактное числовое поле строки кабинета: одинаковые отступы и клавиатура
/// у остатка и срока, чтобы строка не разъезжалась по высоте.
class _NumField extends StatelessWidget {
  const _NumField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.hint,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool decimal;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
      ],
      onChanged: (_) => onChanged(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}
