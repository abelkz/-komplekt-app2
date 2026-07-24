import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/supplier_cabinet_repository.dart';
import '../supplier_cabinet_providers.dart';
import 'add_product_sheet.dart';

/// Шаг перед созданием товара: не завёл ли его уже кто-то другой.
///
/// В общем каталоге карточка товара одна на всех: название, фото и
/// заводской артикул общие, а цены у каждого поставщика свои. Поэтому
/// сначала ищем существующую карточку и добавляем цену к ней — и только
/// если товара действительно нет, заводим новую.
Future<void> showCatalogPickSheet(BuildContext context, String supplierId) {
  // Полноэкранная страница, а не нижний лист: с клавиатурой и фото-пикером
  // на iOS/вебе лист «улетал». У страницы поле остаётся на месте.
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _CatalogPickSheet(supplierId: supplierId),
  ));
}

class _CatalogPickSheet extends ConsumerStatefulWidget {
  const _CatalogPickSheet({required this.supplierId});
  final String supplierId;

  @override
  ConsumerState<_CatalogPickSheet> createState() => _CatalogPickSheetState();
}

class _CatalogPickSheetState extends ConsumerState<_CatalogPickSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<CatalogMatch> _found = const [];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _found = const [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final list = await ref
        .read(supplierCabinetRepositoryProvider)
        .searchCatalog(_query.text, widget.supplierId);
    if (!mounted) return;
    setState(() {
      _found = list;
      _searching = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Добавить товар')),
      // Тело — обычный прокручиваемый список на полной странице: клавиатура
      // сдвигает содержимое штатно, ничего не «улетает».
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Сначала поищите товар в каталоге — если его уже завёл другой '
            'поставщик, добавьте свою цену к той же карточке.',
            style: TextStyle(fontSize: 13, color: c.gray, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _query,
            autofocus: true,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Название или артикул производителя',
              hintText: 'DD640200R или «керамогранит Estima»',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),

          if (_found.isNotEmpty)
            ..._found.expand((m) => [
                  _MatchRow(match: m, onTap: () => _addPrice(m)),
                  const SizedBox(height: 8),
                ])
          else if (_searched && !_searching)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('В каталоге такого нет — заведите карточку',
                  style: TextStyle(fontSize: 13, color: c.gray)),
            ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.ink,
                side: BorderSide(color: c.line),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Нет в каталоге — создать карточку'),
              onPressed: () {
                Navigator.pop(context);
                showAddProductSheet(context, widget.supplierId);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addPrice(CatalogMatch match) async {
    if (match.mine) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Этот товар уже есть в вашем прайсе')));
      return;
    }
    final navigator = Navigator.of(context);
    final result = await navigator.push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _PriceForMatchSheet(match: match, supplierId: widget.supplierId),
    ));
    if (result == true) navigator.pop();
  }
}

/// Строка найденной карточки каталога.
class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.onTap});
  final CatalogMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: match.mine ? c.line : c.accent),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: match.imageUrl == null
                  ? Container(color: c.field)
                  : CachedNetworkImage(
                      imageUrl: match.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: c.field),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(match.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (match.brandName != null && match.brandName!.isNotEmpty)
                        match.brandName!,
                      if (match.sku != null && match.sku!.isNotEmpty)
                        'арт. ${match.sku}',
                      if (match.offersCount > 0)
                        'предложений: ${match.offersCount}',
                      if (match.minPrice != null)
                        'от ${Formatters.price(match.minPrice!)}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.gray),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(match.mine ? 'уже ваш' : 'моя цена →',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: match.mine ? c.faint : c.accent)),
          ],
        ),
      ),
    );
  }
}

/// Своя цена к чужой карточке: фото и название не трогаем — они общие.
class _PriceForMatchSheet extends ConsumerStatefulWidget {
  const _PriceForMatchSheet({required this.match, required this.supplierId});
  final CatalogMatch match;
  final String supplierId;

  @override
  ConsumerState<_PriceForMatchSheet> createState() =>
      _PriceForMatchSheetState();
}

class _PriceForMatchSheetState extends ConsumerState<_PriceForMatchSheet> {
  final _price = TextEditingController();
  final _sku = TextEditingController();
  bool _inStock = true;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    _sku.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    if (price == null || price <= 0) {
      setState(() => _error = 'Укажите корректную цену');
      return;
    }
    final ok = await ref.read(cabinetControllerProvider.notifier).addOfferToProduct(
          productId: widget.match.id,
          supplierId: widget.supplierId,
          price: price,
          inStock: _inStock,
          supplierSku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ваша цена добавлена ✓')));
    } else {
      final e = ref.read(cabinetControllerProvider).error;
      setState(() => _error = e.toString().replaceFirst('Failure: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final loading = ref.watch(cabinetControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Ваша цена')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(widget.match.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            'Карточка общая: название и фото менять не нужно — покупатель '
            'увидит вашу цену рядом с ценами других поставщиков.',
            style: TextStyle(fontSize: 12, color: c.gray, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _price,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Цена, ₸ *', suffixText: 'за ${widget.match.unit}'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sku,
            decoration: const InputDecoration(
              labelText: 'Ваш внутренний код',
              hintText: 'необязательно — по нему обновляется ваш прайс',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_inStock ? 'В наличии' : 'Под заказ'),
            value: _inStock,
            activeColor: c.green,
            onChanged: (v) => setState(() => _inStock = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: c.red, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: loading ? null : _save,
              child: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.brandInk))
                  : const Text('Добавить в мой прайс'),
            ),
          ),
        ],
      ),
    );
  }
}
