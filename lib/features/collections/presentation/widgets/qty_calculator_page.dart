import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../catalog/domain/product.dart';

/// Расчёт количества материала: сколько нужно по объекту, плюс запас
/// на подрезку, с округлением вверх до целых упаковок.
///
/// Без него смета врёт дважды: плитку кладут с подрезкой (кусок из угла
/// в дело уже не идёт), а продают её коробками — 38 м² превращаются
/// в 42 м² с запасом и в 7 коробок по 6 м², то есть в 42 м² к оплате.
///
/// Возвращает итоговое количество в единицах товара или null, если
/// расчёт отменили.
Future<double?> showQtyCalculator(
  BuildContext context,
  Product product, {
  double? initial,
}) {
  return Navigator.of(context).push<double>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _QtyCalculatorPage(product: product, initial: initial),
  ));
}

/// Чистый расчёт расхода — отдельно от экрана, чтобы его можно было
/// проверить тестами: ошибка здесь стоит денег на объекте.
class QtyCalc {
  const QtyCalc({
    required this.base,
    required this.sparePercent,
    this.packQty,
    this.unit = 'шт',
  });

  /// Сколько нужно по объекту, до запаса.
  final double base;

  /// Запас на подрезку в процентах.
  final int sparePercent;

  /// Сколько единиц в упаковке. null или не больше нуля — фасовки нет.
  final double? packQty;

  final String unit;

  /// В упаковке меньше или ровно ноль — значит фасовки по сути нет
  /// (поставщик вписал мусор), считаем без коробок.
  double? get pack => (packQty == null || packQty! <= 0) ? null : packQty;

  /// Сколько выходит с запасом, до округления по упаковкам.
  double get withSpare => base * (1 + sparePercent / 100);

  /// Сколько упаковок придётся купить: только вверх — половину коробки
  /// плитки никто не продаст.
  int? get packs {
    final p = pack;
    if (p == null) return null;
    final raw = withSpare / p;
    // Плавающая точка: 14.4 / 1.44 выходит не ровно 10, а 10.000000000000002,
    // и честное округление вверх приписало бы лишнюю коробку на ровном месте.
    final nearest = raw.roundToDouble();
    if ((raw - nearest).abs() < 1e-9) return nearest.toInt();
    return raw.ceil();
  }

  /// Итог, который уедет в смету.
  double get total {
    final p = pack, n = packs;
    if (p != null && n != null) return n * p;
    // Штучный товар дробным не бывает — округляем вверх.
    return unit == 'шт' ? withSpare.ceilToDouble() : withSpare;
  }
}

class _QtyCalculatorPage extends StatefulWidget {
  const _QtyCalculatorPage({required this.product, this.initial});

  final Product product;
  final double? initial;

  @override
  State<_QtyCalculatorPage> createState() => _QtyCalculatorPageState();
}

class _QtyCalculatorPageState extends State<_QtyCalculatorPage> {
  late final TextEditingController _need;

  /// Запас на подрезку в процентах. 10 % — то, что кладут по умолчанию
  /// при прямой раскладке; для диагонали берут 15 %.
  int _spare = 10;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    _need = TextEditingController(text: v == null ? '' : Formatters.number(v));
  }

  @override
  void dispose() {
    _need.dispose();
    super.dispose();
  }

  double? get _base {
    final raw = _need.text.trim().replaceAll(',', '.').replaceAll(' ', '');
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return null;
    return v;
  }

  /// null, пока в поле не введено осмысленное число.
  QtyCalc? get _calc {
    final b = _base;
    if (b == null) return null;
    return QtyCalc(
      base: b,
      sparePercent: _spare,
      packQty: widget.product.packQty,
      unit: widget.product.unit,
    );
  }

  void _apply() {
    final c = _calc;
    if (c == null) return;
    Navigator.pop(context, c.total);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.product;
    final calc = _calc;
    final total = calc?.total;
    final packs = calc?.packs;
    // Фасовку показываем и до ввода числа: строка «Упаковок по 1.44 м²»
    // сразу объясняет, почему итог не совпадёт с введённой площадью.
    final pack = (p.packQty == null || p.packQty! <= 0) ? null : p.packQty;
    final best = p.bestOffer;

    return Scaffold(
      appBar: AppBar(title: const Text('Расчёт количества')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(p.name, style: AppTypography.titleMd(color: c.ink)),
          const SizedBox(height: 16),
          TextField(
            controller: _need,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _needLabel(p.unit),
              hintText: '38',
              suffixText: p.unit,
            ),
          ),
          const SizedBox(height: 22),
          Text('ЗАПАС НА ПОДРЕЗКУ',
              style: AppTypography.sectionLabel(color: c.faint)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final v in const [0, 5, 10, 15])
                _SpareChip(
                  percent: v,
                  selected: _spare == v,
                  onTap: () => setState(() => _spare = v),
                ),
            ],
          ),
          const SizedBox(height: 22),
          // Показываем весь ход расчёта, а не только итог: смету потом
          // защищают перед заказчиком, и «откуда 42 м²» там спросят.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.card,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Column(
              children: [
                _Line(
                  label: 'По объекту',
                  value: _qtyText(_base, p.unit),
                ),
                _Line(
                  label: 'С запасом $_spare %',
                  value: _qtyText(calc?.withSpare, p.unit),
                ),
                if (pack != null)
                  _Line(
                    label: 'Упаковок по ${Formatters.number(pack)} ${p.unit}',
                    value: packs == null ? '—' : '$packs',
                  ),
                Divider(height: 22, thickness: 1, color: c.line),
                Row(
                  children: [
                    Expanded(
                      child: Text('Итого к закупке',
                          style: AppTypography.bodyMd(color: c.ink)),
                    ),
                    Text(_qtyText(total, p.unit),
                        style: AppTypography.priceLg(color: c.accent)),
                  ],
                ),
                if (best != null && total != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text('По лучшей цене',
                            style: AppTypography.bodySm(color: c.faint)),
                      ),
                      Text(Formatters.price(best.price * total),
                          style: AppTypography.data(color: c.gray)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (pack == null) ...[
            const SizedBox(height: 10),
            Text(
              'Поставщик не указал фасовку — считаем без округления '
              'до упаковок.',
              style: AppTypography.bodySm(color: c.faint),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: total == null ? null : _apply,
              child: const Text('Поставить в смету'),
            ),
          ),
        ],
      ),
    );
  }

  /// «Площадь» для м², «длина» для погонных метров — у объёма и штук
  /// такого слова нет, там спрашиваем прямо.
  static String _needLabel(String unit) {
    switch (unit) {
      case 'м²':
        return 'Площадь';
      case 'м':
        return 'Длина';
      default:
        return 'Сколько нужно';
    }
  }

  static String _qtyText(double? v, String unit) =>
      v == null ? '—' : '${Formatters.number(v)} $unit';
}

/// Строка расчёта: подпись слева, число справа.
class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.bodySm(color: c.gray))),
          Text(value, style: AppTypography.data(color: c.ink)),
        ],
      ),
    );
  }
}

class _SpareChip extends StatelessWidget {
  const _SpareChip({
    required this.percent,
    required this.selected,
    required this.onTap,
  });

  final int percent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.field,
          border: Border.all(color: selected ? c.accent : c.line),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Text(
          percent == 0 ? 'без запаса' : '+$percent %',
          style: AppTypography.bodySm(
              color: selected ? AppColors.brandInk : c.gray),
        ),
      ),
    );
  }
}
