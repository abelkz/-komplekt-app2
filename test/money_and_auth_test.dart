import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komplekt/core/config/pricing.dart';
import 'package:komplekt/core/utils/phone_input.dart';
import 'package:komplekt/features/auth/data/auth_repository.dart';
import 'package:komplekt/features/auth/domain/app_user.dart';
import 'package:komplekt/features/suppliers_map/domain/supplier.dart';

void main() {
  // ── Цены: единый прайс не «уехал» ──────────────────────────────────────
  group('Pricing', () {
    test('значения не изменились случайной правкой', () {
      expect(Pricing.clientPro, 4900);
      expect(Pricing.supplierPro, 9900);
      expect(Pricing.boost, {1: 1500, 3: 3500, 7: 7000});
    });
    test('сроки буста по возрастанию', () {
      expect(Pricing.boostDays, [1, 3, 7]);
    });
  });

  // ── Кто считается Pro (клиент) ─────────────────────────────────────────
  group('AppUser.isPro', () {
    AppUser u(String plan, DateTime? until) =>
        AppUser(id: '1', plan: plan, planUntil: until);

    test('free — не Pro', () => expect(u('free', null).isPro, false));
    test('pro без даты — Pro бессрочно',
        () => expect(u('pro', null).isPro, true));
    test('pro с будущей датой — Pro', () {
      expect(u('pro', DateTime.now().add(const Duration(days: 5))).isPro, true);
    });
    test('pro с прошедшей датой — НЕ Pro (тариф истёк)', () {
      expect(
          u('pro', DateTime.now().subtract(const Duration(days: 1))).isPro,
          false);
    });
  });

  // ── Кто считается Pro (поставщик) + годы на рынке ──────────────────────
  group('Supplier', () {
    Supplier s({String plan = 'free', DateTime? until, int? since}) => Supplier(
        id: '1', name: 'К', plan: plan, planUntil: until, sinceYear: since);

    test('истёкший тариф поставщика — не Pro', () {
      expect(
          s(plan: 'pro', until: DateTime.now().subtract(const Duration(days: 1)))
              .isPro,
          false);
    });
    test('действующий тариф — Pro', () {
      expect(
          s(plan: 'pro', until: DateTime.now().add(const Duration(days: 1)))
              .isPro,
          true);
    });
    test('годы на рынке считаются от года начала', () {
      final y = DateTime.now().year - 5;
      expect(s(since: y).yearsOnMarket, 5);
    });
    test('без года начала — null', () => expect(s().yearsOnMarket, null));
  });

  // ── Номер телефона -> служебный логин ──────────────────────────────────
  group('phoneToEmail', () {
    test('формат с пробелами игнорируется', () {
      expect(AuthRepository.phoneToEmail('+7 700 000 0000'),
          '77000000000@example.com');
    });
    test('8 в начале превращается в 7', () {
      expect(AuthRepository.phoneToEmail('8 700 123 45 67'),
          '77001234567@example.com');
    });
    test('10 цифр дополняются кодом', () {
      expect(
          AuthRepository.phoneToEmail('7000000000'), '77000000000@example.com');
    });
    test('уже email — возвращается как есть', () {
      expect(AuthRepository.phoneToEmail('me@mail.kz'), 'me@mail.kz');
    });
    test('мусор — null', () {
      expect(AuthRepository.phoneToEmail('абв'), null);
    });
  });

  // ── Маска ввода номера ─────────────────────────────────────────────────
  group('KzPhoneInputFormatter', () {
    const f = KzPhoneInputFormatter();
    String fmt(String input) => f
        .formatEditUpdate(
          const TextEditingValue(text: ''),
          TextEditingValue(text: input),
        )
        .text;

    test('полный номер группируется 3-3-4', () {
      expect(fmt('77000000000'), '+7 700 000 0000');
    });
    test('частичный ввод (в поле уже есть +7)', () {
      expect(fmt('+7 700'), '+7 700');
    });
    test('пустой ввод даёт код страны', () {
      expect(fmt(''), '+7');
    });
  });
}
