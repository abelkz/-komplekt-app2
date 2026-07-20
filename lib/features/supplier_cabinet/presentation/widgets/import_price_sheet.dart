import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../catalog/presentation/catalog_providers.dart';
import '../../data/supplier_cabinet_repository.dart';
import '../supplier_cabinet_providers.dart';

Future<void> showImportPriceSheet(BuildContext context, String supplierId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ImportPriceSheet(supplierId: supplierId),
  );
}

class _ImportPriceSheet extends ConsumerStatefulWidget {
  const _ImportPriceSheet({required this.supplierId});
  final String supplierId;
  @override
  ConsumerState<_ImportPriceSheet> createState() => _ImportPriceSheetState();
}

class _ImportPriceSheetState extends ConsumerState<_ImportPriceSheet> {
  List<String> _headers = [];
  List<List<String>> _rows = [];
  String? _error;
  bool _parsing = false;

  // выбранные колонки (индекс в _headers) и категория
  int? _name, _price, _sku, _unit, _img;
  String? _category;

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _parsing = true;
    });
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      final file = res?.files.single;
      final bytes = file?.bytes;
      if (bytes == null) {
        setState(() => _parsing = false);
        return;
      }

      final isCsv = (file!.extension ?? '').toLowerCase() == 'csv';
      final ok = isCsv ? _parseCsv(bytes) : _parseExcel(bytes);
      if (!ok) {
        setState(() => _parsing = false);
        return;
      }

      _guessColumns();
      setState(() => _parsing = false);
    } catch (e) {
      setState(() {
        _error = 'Не удалось прочитать файл: $e';
        _parsing = false;
      });
    }
  }

  bool _parseExcel(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    final all = sheet.rows;
    if (all.length < 2) {
      _error = 'В файле нет данных (нужны заголовки и хотя бы одна строка)';
      return false;
    }
    _headers = [
      for (var i = 0; i < all.first.length; i++)
        () {
          final v = all.first[i]?.value?.toString().trim() ?? '';
          return v.isEmpty ? 'Колонка ${i + 1}' : v;
        }(),
    ];
    _rows = all
        .skip(1)
        .map((r) => [
              for (var i = 0; i < _headers.length; i++)
                (i < r.length ? r[i]?.value?.toString() ?? '' : '')
            ])
        .toList();
    return true;
  }

  bool _parseCsv(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter()
        .convert(text)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      _error = 'В CSV нет данных (нужны заголовки и хотя бы одна строка)';
      return false;
    }
    // Разделитель: ';' (часто в RU-локали Excel) или ','
    final delim = lines.first.contains(';') ? ';' : ',';
    List<String> split(String line) => line
        .split(delim)
        .map((c) => c.trim().replaceAll(RegExp(r'^"|"$'), ''))
        .toList();

    final head = split(lines.first);
    _headers = [
      for (var i = 0; i < head.length; i++)
        head[i].isEmpty ? 'Колонка ${i + 1}' : head[i],
    ];
    _rows = lines.skip(1).map((l) {
      final cells = split(l);
      return [
        for (var i = 0; i < _headers.length; i++)
          (i < cells.length ? cells[i] : '')
      ];
    }).toList();
    return true;
  }

  void _guessColumns() {
    int? guess(List<String> words) {
      for (var i = 0; i < _headers.length; i++) {
        final h = _headers[i].toLowerCase();
        if (words.any(h.contains)) return i;
      }
      return null;
    }

    _name = guess(['назв', 'товар', 'наимен', 'name', 'product']);
    _price = guess(['цена', 'price', 'стоим', 'тенге', 'тг']);
    _sku = guess(['артик', 'sku', 'код', 'art']);
    _unit = guess(['ед', 'изм', 'unit']);
    _img = guess(['фото', 'image', 'img', 'картин', 'ссыл']);
  }

  int get _validCount {
    if (_name == null || _price == null) return 0;
    var n = 0;
    for (final r in _rows) {
      final name = r[_name!].trim();
      final price = _parsePrice(r[_price!]);
      if (name.isNotEmpty && price != null && price > 0) n++;
    }
    return n;
  }

  static double? _parsePrice(String s) {
    final cleaned =
        s.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned);
  }

  Future<void> _import() async {
    setState(() => _error = null);
    if (_name == null || _price == null) {
      setState(() => _error = 'Укажите колонки «Название» и «Цена»');
      return;
    }
    if (_category == null) {
      setState(() => _error = 'Выберите категорию для товаров');
      return;
    }
    final priceRows = <PriceRow>[];
    for (final r in _rows) {
      final name = r[_name!].trim();
      final price = _parsePrice(r[_price!]);
      if (name.isEmpty || price == null || price <= 0) continue;
      priceRows.add(PriceRow(
        name: name,
        price: price,
        sku: _sku != null ? (r[_sku!].trim().isEmpty ? null : r[_sku!].trim()) : null,
        unit: _unit != null && r[_unit!].trim().isNotEmpty ? r[_unit!].trim() : 'шт',
        imageUrl: _img != null && r[_img!].trim().isNotEmpty ? r[_img!].trim() : null,
      ));
    }
    final n = await ref.read(cabinetControllerProvider.notifier).importPrice(
          rows: priceRows,
          categorySlug: _category!,
          supplierId: widget.supplierId,
        );
    if (!mounted) return;
    if (n >= 0) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Загружено товаров: $n')));
    } else {
      final e = ref.read(cabinetControllerProvider).error;
      setState(() => _error = e.toString().replaceFirst('Failure: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final loading = ref.watch(cabinetControllerProvider).isLoading;
    final hasFile = _headers.isNotEmpty;

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
            const Text('Загрузка прайса из Excel',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Поддерживаются .xlsx, .xls и .csv. Укажите, в каких колонках '
                'название и цена — остальное необязательно.',
                style: TextStyle(fontSize: 12, color: c.gray)),
            const SizedBox(height: 16),

            if (!hasFile)
              OutlinedButton.icon(
                onPressed: _parsing ? null : _pick,
                icon: const Icon(Icons.attach_file),
                label: Text(_parsing ? 'Читаю файл…' : 'Выбрать файл прайса'),
              )
            else ...[
              Text('Найдено строк: ${_rows.length} · к загрузке: $_validCount',
                  style: TextStyle(fontSize: 13, color: c.gray)),
              const SizedBox(height: 14),
              _ColumnPicker(
                  label: 'Название товара *',
                  value: _name,
                  headers: _headers,
                  onChanged: (v) => setState(() => _name = v)),
              _ColumnPicker(
                  label: 'Цена *',
                  value: _price,
                  headers: _headers,
                  onChanged: (v) => setState(() => _price = v)),
              _ColumnPicker(
                  label: 'Артикул',
                  value: _sku,
                  headers: _headers,
                  optional: true,
                  onChanged: (v) => setState(() => _sku = v)),
              _ColumnPicker(
                  label: 'Ед. изм.',
                  value: _unit,
                  headers: _headers,
                  optional: true,
                  onChanged: (v) => setState(() => _unit = v)),
              _ColumnPicker(
                  label: 'Ссылка на фото',
                  value: _img,
                  headers: _headers,
                  optional: true,
                  onChanged: (v) => setState(() => _img = v)),
              DropdownButtonFormField<String>(
                value: _category,
                decoration:
                    const InputDecoration(labelText: 'Категория для всех *'),
                items: [
                  for (final cat in categories)
                    DropdownMenuItem(value: cat.slug, child: Text(cat.name)),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: c.red)),
            ],

            if (hasFile) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: loading ? null : _import,
                  child: loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.brandInk))
                      : Text('Загрузить товары ($_validCount)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColumnPicker extends StatelessWidget {
  const _ColumnPicker({
    required this.label,
    required this.value,
    required this.headers,
    required this.onChanged,
    this.optional = false,
  });

  final String label;
  final int? value;
  final List<String> headers;
  final ValueChanged<int?> onChanged;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          if (optional)
            const DropdownMenuItem<int?>(value: null, child: Text('— нет —')),
          for (var i = 0; i < headers.length; i++)
            DropdownMenuItem<int?>(value: i, child: Text(headers[i])),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
