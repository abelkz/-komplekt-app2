import 'package:flutter_test/flutter_test.dart';
import 'package:komplekt/core/router/app_router.dart';

/// Гостевой доступ к каталогу — не косметика, а воронка: человек должен
/// увидеть товар до того, как его попросят зарегистрироваться.
///
/// Тест появился после боевой ошибки в 1.0.1: список закрытых разделов
/// проверялся через `startsWith('/pro')`, и под него попадали `/product/:id`
/// и `/profile`. Гостя выбрасывало из карточки товара и из вкладки профиля,
/// а вместе со вторым багом в redirect это давало цикл и молчаливый возврат
/// на главную — снаружи «карточки просто не открываются».
void main() {
  group('Гостю открыто', () {
    for (final path in [
      '/home',
      '/favorites',
      '/collections',
      '/profile', // на месте вкладки показывается SignInRequired
      '/product/2',
      '/product/00000000-0000-0000-0000-000000000001',
      '/catalog/plitka',
      '/supplier/7',
      '/map',
      '/search',
      '/auth',
      '/onboarding',
      '/new-password',
      '/visual-search',
    ]) {
      test(path, () => expect(needsAccount(path), false));
    }
  });

  group('Гостю закрыто — нужен аккаунт', () {
    for (final path in [
      '/supplier-cabinet',
      '/supplier-cabinet/location',
      '/notifications',
      '/admin',
      '/pro',
    ]) {
      test(path, () => expect(needsAccount(path), true));
    }
  });

  test('префикс платного раздела не ловит соседние пути', () {
    // Именно эта пара и сломалась в 1.0.1.
    expect(needsAccount('/pro'), true);
    expect(needsAccount('/product/1'), false);
    expect(needsAccount('/profile'), false);
  });
}
