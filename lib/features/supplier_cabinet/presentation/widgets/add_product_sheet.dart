import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../catalog/presentation/catalog_providers.dart';
import '../supplier_cabinet_providers.dart';

Future<void> showAddProductSheet(BuildContext context, String supplierId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddProductSheet(supplierId: supplierId),
  );
}

class _AddProductSheet extends ConsumerStatefulWidget {
  const _AddProductSheet({required this.supplierId});
  final String supplierId;
  @override
  ConsumerState<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends ConsumerState<_AddProductSheet> {
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _price = TextEditingController();
  final _img = TextEditingController();
  String _unit = 'шт';
  bool _inStock = true;
  String? _category;
  String? _error;
  bool _uploading = false;
  String? _photoUrl; // загруженное фото (публичный URL)

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
    for (final c in [_name, _sku, _price, _img]) {
      c.dispose();
    }
    super.dispose();
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
    final ok = await ref.read(cabinetControllerProvider.notifier).addProduct(
          name: name,
          categorySlug: _category!,
          unit: _unit,
          price: price,
          inStock: _inStock,
          supplierId: widget.supplierId,
          sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
          imageUrl: _img.text.trim().isEmpty ? null : _img.text.trim(),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Товар добавлен ✓')));
    } else {
      final e = ref.read(cabinetControllerProvider).error;
      setState(() => _error = e.toString().replaceFirst('Failure: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final loading = ref.watch(cabinetControllerProvider).isLoading;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Новый товар',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Название *', hintText: 'Керамогранит … 60×60'),
            ),
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
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
}
