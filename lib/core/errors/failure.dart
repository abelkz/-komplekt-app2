/// Типизированная ошибка для слоя данных.
/// Репозитории ловят исключения Supabase и оборачивают их в Failure
/// с понятным русским сообщением для UI.
class Failure implements Exception {
  const Failure(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'Failure: $message';
}

/// Преобразует произвольное исключение в человекочитаемое сообщение.
Failure mapError(Object error, {String fallback = 'Что-то пошло не так'}) {
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return const Failure('Нет связи с сервером. Проверьте интернет.');
  }
  if (text.contains('Invalid login')) {
    return const Failure('Неверный email или пароль.');
  }
  if (text.contains('already registered')) {
    return const Failure('Этот email уже зарегистрирован — войдите.');
  }
  if (text.contains('at least 6')) {
    return const Failure('Пароль должен быть не короче 6 символов.');
  }
  return Failure(fallback, error);
}
