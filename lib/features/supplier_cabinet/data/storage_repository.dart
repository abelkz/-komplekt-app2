import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';

/// Загрузка фото товаров в Supabase Storage (бакет product-images).
class StorageRepository {
  const StorageRepository();

  static const _bucket = 'product-images';

  /// Загружает изображение и возвращает публичный URL.
  /// [ext] — расширение файла (jpg/png), нужно для content-type.
  Future<String> uploadProductImage(Uint8List bytes, {String ext = 'jpg'}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw const Failure('Войдите, чтобы загрузить фото');

    // Литерал, а не 1 << 32: в вебе Dart компилируется в JavaScript, где
    // сдвиг считается по 32 битам и 1 << 32 обращается в ноль — отсюда была
    // ошибка «max must be in range 0 < max ≤ 2^32, was 0».
    final rand = Random().nextInt(0x7FFFFFFF).toRadixString(16);
    final path =
        '$uid/${DateTime.now().millisecondsSinceEpoch}_$rand.$ext';
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

    try {
      await supabase.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return supabase.storage.from(_bucket).getPublicUrl(path);
    } catch (e) {
      if (e.toString().contains('Bucket not found')) {
        throw const Failure(
            'Хранилище фото не создано — примените миграцию 0011 в Supabase');
      }
      throw mapError(e, fallback: 'Не удалось загрузить фото');
    }
  }
}
