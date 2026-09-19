import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../catalog/domain/product.dart';
import '../../../catalog/presentation/catalog_providers.dart';
import '../supplier_cabinet_providers.dart';

/// Новый товар.
Future<void> showAddProductSheet(BuildContext context, String supplierId) {
  // Полноэкранная страница — форма с фото и полями корректно работает
  // с клавиатурой и медиатекой (нижний лист на iOS/вебе «улетал»).
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _AddProductSheet(supplierId: supplierId),
  ));
}

/// Правка существующего товара: та же форма, заполненная его данными.
/// Ошиблись категорией или забыли фото — исправляется здесь, а не
/// удалением и созданием заново.
Future<void> showEditProductSheet(
  BuildContext context,
  String supplierId,
  Product product,
) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _AddProductSheet(supplierId: supplierId, product: product),
  ));
}

class _AddProductSheet extends ConsumerStatefulWidget {
  const _AddProductSheet({required this.supplierId, this.product});
  final String supplierId;

  /// null — создаём новый товар, иначе правим этот
  final Product? product;

  @override
  ConsumerState<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends ConsumerState<_AddProductSheet> {
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _brand = TextEditingController();
  final _price = TextEditingController();
  final _img = TextEditingController();
  // Данные из миграции 0029 — то, что карточка товара обещает покупателю
  final _pack = TextEditingController();
  final _warranty = TextEditingController();
  final _attrs = TextEditingController();
  final _stock = TextEditingController();
  final _lead = TextEditingController();
  String _unit = 'шт';
  bool _inStock = true;
  String? _category;
  String? _error;
  bool _uploading = false;
  String? _photoUrl; // загруженное фото (публичный URL)

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p == null) return;
    _name.text = p.name;
    _sku.text = p.sku;
    _brand.text = p.brand;
    _unit = _units.contains(p.unit) ? p.unit : 'шт';
    _category = p.categorySlug;
    _img.text = p.primaryImageUrl ?? '';
    _photoUrl = p.primaryImageUrl;
    _pack.text = _num(p.packQty);
    _warranty.text = p.warrantyMonths?.toString() ?? '';
    _attrs.text = p.attrs.join(', ');
    final offer = p.offers.isNotEmpty ? p.offers.first : null;
    if (offer != null) {
      _price.text = offer.price.toStringAsFixed(0);
      _inStock = offer.inStock;
      _stock.text = _num(offer.stockQty);
      _lead.text = offer.leadTimeDays?.toString() ?? '';
    }
  }

  /// Без хвоста «.0»: в поле фасовки должно стоять 1.44, но 12 — а не 12.0.
  static String _num(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _error = null;
      _uploading = true;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (picked == null) {
        setState(() => _uploading = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final ext = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final url = await ref
          .read(storageRepositoryProvider)
          .uploadProductImage(bytes, ext: ext);
      setState(() {
        _photoUrl = url;
        _img.text = url; // используем тот же путь сохранения, что и URL
        _uploading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Failure: ', '');
        _uploading = false;
      });
    }
  }

  static const _units = ['шт', 'м²', 'м', 'л', 'кг', 'упак'];

  @override
  void dispose() {
    for (final c in [
      _name,
      _sku,
      _brand,
      _price,
      _img,
      _pack,
      _warranty,
      _attrs,
      _stock,
      _lead,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Разбор необязательного числового поля: пусто — значит «не указано»,
  /// и это законный ответ. Ошибку возвращаем только на непустой мусор.
  _Parsed _parse(TextEditingController c, String label,
      {bool integer = false}) {
    final raw = c.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return const _Parsed(null);
    final v = integer ? int.tryParse(raw)?.toDouble() : double.tryParse(raw);
    if (v == null || v < 0) {
      return _Parsed(null,
          error: integer
              ? '$label — целое число, не меньше нуля'
              : '$label — число, не меньше нуля');
    }
    return _Parsed(v);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    if (name.isEmpty) {
      setState(() => _error = 'Укажите название товара');
      return;
    }
    if (_category == null) {
      setState(() => _error = 'Выберите категорию');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Укажите корректную цену');
      return;
    }
    // Пустое поле — «не указано», это нормально. Но если поставщик что-то
    // ввёл, а числом это не является, молча выбрасывать введённое нельзя.
    final pack = _parse(_pack, 'Фасовка');
    if (pack.invalid) {
      setState(() => _error = pack.error);
      return;
    }
    final warranty = _parse(_warranty, 'Гарантия', integer: true);
    if (warranty.invalid) {
      setState(() => _error = warranty.error);
      return;
    }
    final stock = _parse(_stock, 'Остаток');
    if (stock.invalid) {
      setState(() => _error = stock.error);
      return;
    }
    final lead = _parse(_lead, 'Срок поставки', integer: true);
    if (lead.invalid) {
      setState(() => _error = lead.error);
      return;
    }

    final ctrl = ref.read(cabinetControllerProvider.notifier);
    final sku = _sku.text.trim().isEmpty ? null : _sku.text.trim();
    final img = _img.text.trim().isEmpty ? null : _img.text.trim();
    final attrs = [
      for (final a in _attrs.text.split(','))
        if (a.trim().isNotEmpty) a.trim(),
    ];

    bool ok;
    if (_editing) {
      final p = widget.product!;
      ok = await ctrl.updateProduct(
        productId: p.id,
        name: name,
        categorySlug: _category!,
        unit: _unit,
        sku: sku,
        imageUrl: img,
        packQty: pack.value,
        warrantyMonths: warranty.value?.toInt(),
        attrs: attrs,
        brand: _brand.text,
      );
      // цена живёт в предложении — сохраняем её отдельно
      if (ok) {
        ok = await ctrl.saveOffer(
          offerId: p.offers.isNotEmpty ? p.offers.first.id : null,
          productId: p.id,
          supplierId: widget.supplierId,
          price: price,
          inStock: _inStock,
          stockQty: stock.value,
          leadTimeDays: lead.value?.toInt(),
        );
      }
    } else {
      ok = await ctrl.addProduct(
        name: name,
        categorySlug: _category!,
        unit: _unit,
        price: price,
        inStock: _inStock,
        supplierId: widget.supplierId,
        sku: sku,
        imageUrl: img,
        packQty: pack.value,
        warrantyMonths: warranty.value?.toInt(),
        attrs: attrs,
        stockQty: stock.value,
        leadTimeDays: lead.value?.toInt(),
        brand: _brand.text,
      );
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editing ? 'Товар изменён ✓' : 'Товар добавлен ✓')));
    } else {
      final e = ref.read(cabinetControllerProvider).error;
      setState(() => _error = e.toString().replaceFirst('Failure: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(categoriesProvider);
    final categories = catsAsync.valueOrNull ?? const [];
    final loading = ref.watch(cabinetControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
          title: Text(_editing ? 'Изменить товар' : 'Новый товар')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Название *', hintText: 'Керамогранит … 60×60'),
            ),
            const SizedBox(height: 12),
            // Марка: подсказываем уже заведённые, но не запрещаем новую.
            // Без этого поля марку вписать было негде вообще, и в каталоге
            // накопились чужие: «Переключатель Schneider Electric» числился
            // под маркой Cersanit. Сравнение цен по марке на таких данных
            // не работает.
            _BrandField(controller: _brand),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sku,
                    decoration: const InputDecoration(labelText: 'Артикул'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _unit,
                    decoration: const InputDecoration(labelText: 'Ед. изм.'),
                    items: [
                      for (final u in _units)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (v) => setState(() => _unit = v ?? 'шт'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Пока категории не загрузились, список пуст и выпадашка мертва —
            // поэтому показываем, что именно происходит, и даём повторить.
            if (categories.isEmpty)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Категория *',
                  errorText: catsAsync.hasError
                      ? 'Не удалось загрузить категории'
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        catsAsync.isLoading
                            ? 'Загружаю категории…'
                            : 'Категорий нет',
                        style: TextStyle(color: context.colors.gray),
                      ),
                    ),
                    if (!catsAsync.isLoading)
                      TextButton(
                        onPressed: () => ref.invalidate(categoriesProvider),
                        child: const Text('Повторить'),
                      ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Категория *'),
                items: [
                  for (final cat in categories)
                    DropdownMenuItem(value: cat.slug, child: Text(cat.name)),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Цена, ₸ *', hintText: '4500'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Switch(
                        value: _inStock,
                        onChanged: (v) => setState(() => _inStock = v),
                      ),
                      Flexible(
                          child: Text(_inStock ? 'В наличии' : 'Под заказ',
                              style: const TextStyle(fontSize: 12))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Остаток и срок — это про конкретного поставщика, поэтому живут
            // в предложении. По ним покупатель планирует закупку, и пустое
            // поле честнее выдуманного числа: тогда карточка просто молчит.
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _stock,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: 'Остаток, $_unit', hintText: 'сколько есть'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lead,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Срок, дней', hintText: '0 — со склада'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Фасовка и гарантия — свойства самой карточки, общие для всех
            // поставщиков. Фасовка нужна расчёту: «нужно 38 м²» превращается
            // в «7 коробок» только если известно, сколько в коробке.
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pack,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: 'В упаковке, $_unit', hintText: '1.44'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _warranty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Гарантия, мес.', hintText: '60'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _attrs,
              decoration: const InputDecoration(
                labelText: 'Характеристики',
                hintText: 'Матовая, R10, ректифицированный',
                helperText: 'Через запятую — покажем списком в карточке',
              ),
            ),
            const SizedBox(height: 12),
            // Фото: загрузка с устройства (или ссылкой ниже)
            Row(
              children: [
                if (_photoUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      child: Image.network(_photoUrl!,
                          width: 52, height: 52, fit: BoxFit.cover),
                    ),
                  ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickPhoto,
                    icon: _uploading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text(_uploading
                        ? 'Загружаю…'
                        : (_photoUrl != null ? 'Заменить фото' : 'Фото с устройства')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _img,
              decoration: const InputDecoration(
                  labelText: '…или ссылка на фото',
                  hintText: 'https://…/photo.jpg'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: context.colorScheme.error)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: loading ? null : _save,
                child: loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.brandInk))
                    : const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Поле марки с подсказками из уже заведённых.
///
/// Не выпадающий список: марки, которой нет в каталоге, иначе не вписать,
/// а поставщик первым и приносит новые. Но и не голое поле: подсказка не
/// даёт завести седьмое написание «Kerama Marazzi».
class _BrandField extends ConsumerStatefulWidget {
  const _BrandField({required this.controller});
  final TextEditingController controller;

  @override
  ConsumerState<_BrandField> createState() => _BrandFieldState();
}

class _BrandFieldState extends ConsumerState<_BrandField> {
  // Узел фокуса живёт вместе с виджетом, а не создаётся в build: заново
  // созданный на каждой перерисовке, он терял бы фокус прямо во время набора.
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final known = ref.watch(allBrandsProvider).valueOrNull ?? const <String>[];

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return known;
        return known.where((b) => b.toLowerCase().contains(q));
      },
      fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
        controller: ctrl,
        focusNode: focus,
        onSubmitted: (_) => onSubmit(),
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Марка',
          hintText: 'Kerama Marazzi, Cersanit…',
          helperText: 'Можно вписать новую — подскажем уже заведённые',
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        final c = context.colors;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: c.card,
            elevation: 4,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: ConstrainedBox(
              // Без ограничения список марок растянет лист на весь экран,
              // когда их станет много.
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      dense: true,
                      title: Text(o, style: const TextStyle(fontSize: 14)),
                      onTap: () => onSelected(o),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Результат разбора необязательного числового поля.
class _Parsed {
  const _Parsed(this.value, {this.error});
  final double? value;
  final String? error;
  bool get invalid => error != null;
}

extension on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
}
