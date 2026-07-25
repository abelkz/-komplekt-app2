import 'package:flutter_test/flutter_test.dart';
import 'package:komplekt/core/utils/formatters.dart';

// В коде Formatters разделитель разрядов — неразрывный пробел (U+00A0).
// Задаём его через код символа, чтобы в исходнике не было невидимых знаков
// и сравнение точно совпадало с выводом.
final nbsp = String.fromCharCode(0x00A0);

void main() {
  group('Formatters.number', () {
    test('разряды разделяются неразрывным пробелом', () {
      expect(Formatters.number(4290), '4${nbsp}290');
      expect(Formatters.number(1234567), '1${nbsp}234${nbsp}567');
      expect(Formatters.number(100), '100');
    });
  });

  group('Formatters.price', () {
    test('добавляет символ валюты', () {
      // неразрывные пробелы и внутри числа, и перед знаком валюты
      expect(Formatters.price(28900), '28${nbsp}900${nbsp}₸');
    });
  });

  group('Formatters.relativeDate', () {
    test('сегодня для текущего момента', () {
      expect(Formatters.relativeDate(DateTime.now()), 'сегодня');
    });
    test('пустая строка для null', () {
      expect(Formatters.relativeDate(null), '');
    });
  });
}
