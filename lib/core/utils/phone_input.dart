import 'package:flutter/services.dart';

/// Маска ввода казахстанского номера: всегда «+7», национальная часть
/// группируется по 3-3-4 через пробелы — «+7 700 000 0000».
///
/// Форматтер сам держит «+7» впереди, поэтому поле можно предзаполнить
/// значением «+7 7», и человек просто дописывает остальные цифры.
class KzPhoneInputFormatter extends TextInputFormatter {
  const KzPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // «+7» на экране добавляет ведущую 7 (код страны) — убираем её.
    if (digits.startsWith('7') || digits.startsWith('8')) {
      digits = digits.substring(1);
    }
    // Вставили номер вместе с кодом страны ещё раз — уберём повтор.
    if (digits.length > 10 && (digits.startsWith('7') || digits.startsWith('8'))) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) digits = digits.substring(0, 10);

    // Собираем «+7 700 000 0000»
    final buf = StringBuffer('+7');
    if (digits.isNotEmpty) buf.write(' ');
    for (var i = 0; i < digits.length; i++) {
      buf.write(digits[i]);
      if ((i == 2 || i == 5) && i != digits.length - 1) buf.write(' ');
    }
    final text = buf.toString();

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Начальное значение поля: «+7 7» — код страны и первая цифра мобильного.
  static const initial = '+7 7';
}
