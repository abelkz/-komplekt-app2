import 'package:flutter_test/flutter_test.dart';
import 'package:komplekt/core/utils/formatters.dart';

void main() {
  group('Formatters.number', () {
    test('разряды разделяются пробелом', () {
      expect(Formatters.number(4290), '4 290');
      expect(Formatters.number(1234567), '1 234 567');
      expect(Formatters.number(100), '100');
    });
  });

  group('Formatters.price', () {
    test('добавляет символ валюты', () {
      expect(Formatters.price(28900), '28 900 ₸');
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
