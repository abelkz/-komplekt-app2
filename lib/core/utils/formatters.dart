/// Форматирование цен и дат в русском стиле.
class Formatters {
  Formatters._();

  /// 4290 -> "4 290" (неразрывные пробелы между разрядами).
  static String number(num value) {
    final s = value.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// 4290 -> "4 290 ₸"
  static String price(num value, {String currency = '₸'}) =>
      '${number(value)} $currency';

  /// Дата обновления цены -> "сегодня / вчера / N дн. назад".
  static String relativeDate(DateTime? ts) {
    if (ts == null) return '';
    final days = DateTime.now().difference(ts).inDays;
    if (days <= 0) return 'сегодня';
    if (days == 1) return 'вчера';
    if (days < 5) return '$days дня назад';
    return '$days дней назад';
  }
}
