import 'dart:async';

import 'package:http/http.dart' as http;

/// HTTP-клиент для Supabase с ограничением времени на каждый запрос.
///
/// Зачем: без таймаута зависший запрос не падает никогда. Состояние провайдера
/// остаётся `loading`, и вместо понятной ошибки человек видит бесконечный
/// индикатор — приложение выглядит намертво зависшим. Именно так выглядел
/// сбой, когда проект Supabase стоял на паузе: сервер не отвечал, а
/// приложение молча крутило загрузку.
///
/// Таймаут стоит в двух местах: на получении ответа и на паузах между
/// кусками тела — иначе оборванная на середине загрузка тоже висела бы вечно.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 20),
    this.uploadTimeout = const Duration(minutes: 2),
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Обычные запросы: каталог, профиль, авторизация, RPC.
  final Duration timeout;

  /// Загрузка файлов в Storage. Фото товара весит до 5 МБ и на мобильном
  /// интернете идёт заметно дольше обычного запроса, поэтому срок отдельный —
  /// иначе общий таймаут ломал бы загрузку фото в кабинете поставщика.
  final Duration uploadTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final limit = _isUpload(request) ? uploadTimeout : timeout;

    final response = await _inner.send(request).timeout(
          limit,
          onTimeout: () => throw TimeoutException(
              'Сервер не ответил за ${limit.inSeconds} с', limit),
        );

    return http.StreamedResponse(
      response.stream.timeout(
        limit,
        onTimeout: (sink) => sink.addError(
          TimeoutException('Ответ сервера оборвался', limit),
        ),
      ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Отправка файла в Storage — всё, кроме чтения объектов.
  static bool _isUpload(http.BaseRequest request) =>
      request.url.path.contains('/storage/v1/object') &&
      request.method != 'GET';

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
