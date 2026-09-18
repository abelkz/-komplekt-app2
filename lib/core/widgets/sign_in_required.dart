import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import '../theme/app_colors.dart';

/// Заглушка на экранах, которым нужен аккаунт.
///
/// Каталог, поиск и карточки товаров гость смотрит свободно — регистрация
/// просит себя только там, где данные хранятся за пользователем: избранное,
/// подборки, профиль. Показываем это на месте вкладки, а не перебросом на
/// экран входа: человек не должен вылетать из того места, куда он нажал.
class SignInRequired extends StatelessWidget {
  const SignInRequired({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.lock_outline_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.faint),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15, color: c.ink),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.gray),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.push(Routes.auth),
              child: const Text('Войти или зарегистрироваться'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Подсказка для действия, которое гостю недоступно: сердечко, подборка,
/// отзыв. Не перекрывает экран — показывает плашку с кнопкой «Войти».
void promptSignIn(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: 'Войти',
        onPressed: () => context.push(Routes.auth),
      ),
    ));
}
