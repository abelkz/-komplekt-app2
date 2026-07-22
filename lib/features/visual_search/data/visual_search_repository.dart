import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/photo_match.dart';

/// Поиск материалов по фотографии интерьера.
///
/// Сама фотография уходит в серверную функцию `photo-search` — ключ Anthropic
/// лежит там, в секретах Supabase, и в приложение не попадает.
class VisualSearchRepository {
  const VisualSearchRepository();

  Future<PhotoMatch> analyze(Uint8List bytes, {String mediaType = 'image/jpeg'}) async {
    // ~5 МБ base64 — верхняя граница для функции; фото с камеры сжимается
    // на этапе выбора, так что сюда доходит 200-500 КБ.
    if (bytes.lengthInBytes > 4 * 1024 * 1024) {
      throw const Failure('Фото слишком большое — выберите другое');
    }
    try {
      final res = await supabase.functions.invoke(
        'photo-search',
        body: {'image': base64Encode(bytes), 'media_type': mediaType},
      );
      final data = res.data;
      if (data is! Map) throw const Failure('Сервис вернул неожиданный ответ');
      final map = Map<String, dynamic>.from(data);
      if (map['error'] != null) throw Failure(map['error'].toString());
      final match = PhotoMatch.fromMap(map);
      if (match.materials.isEmpty) {
        throw const Failure('На фото не видно отделочных материалов');
      }
      return match;
    } on Failure {
      rethrow;
    } on FunctionException catch (e) {
      // Тело ошибки от функции: {"error": "..."} — показываем его как есть
      final details = e.details;
      if (details is Map && details['error'] != null) {
        throw Failure(details['error'].toString());
      }
      if (e.status == 404) {
        throw const Failure(
            'Поиск по фото ещё не подключён на сервере (функция photo-search не развёрнута)');
      }
      throw mapError(e, fallback: 'Не удалось распознать фото');
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось распознать фото');
    }
  }
}
