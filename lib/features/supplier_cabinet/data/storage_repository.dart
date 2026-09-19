import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';

/// Загрузка изображений в Supabase Storage.
///
/// Два бакета: product-images под фото товаров (0011) и avatars под аватарки
/// людей и логотипы компаний (0031). Раскладка в обоих одна — /<uid>/файл, —
/// потому что политики разрешают писать только в свою папку.
class StorageRepository {
  const StorageRepository();

  static const _products = 'product-images';
  static const _avatars = 'avatars';

  /// Загружает изображение и возвращает публичный URL.
  /// [ext] — расширение файла (jpg/png), нужно для content-type.
  Future<String> uploadProductImage(Uint8List bytes, {String ext = 'jpg'}) =>
      _upload(bytes,
          bucket: _products,
          ext: ext,
          prefix: 'photo',
          missingBucket:
              'Хранилище фото не создано — примените миграцию 0011 в Supabase');

  /// Аватарка пользователя.
  Future<String> uploadAvatar(Uint8List bytes, {String ext = 'jpg'}) =>
      _upload(bytes,
          bucket: _avatars,
          ext: ext,
          prefix: 'user',
          missingBucket:
              'Хранилище аватарок не создано — примените миграцию 0031 '
              'в Supabase');

  /// Логотип компании. Кладём рядом с аватаркой владельца, в его же папку:
  /// политика разрешает писать только туда, а разные имена не дают
  /// перезаписать одно другим.
  Future<String> uploadCompanyLogo(Uint8List bytes, {String ext = 'jpg'}) =>
      _upload(bytes,
          bucket: _avatars,
          ext: ext,
          prefix: 'company',
          missingBucket:
              'Хранилище логотипов не создано — примените миграцию 0031 '
              'в Supabase');

  Future<String> _upload(
    Uint8List bytes, {
    required String bucket,
    required String ext,
    required String prefix,
    required String missingBucket,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw const Failure('Войдите, чтобы загрузить фото');

    // Литерал, а не 1 << 32: в вебе Dart компилируется в JavaScript, где
    // сдвиг считается по 32 битам и 1 << 32 обращается в ноль — отсюда была
    // ошибка «max must be in range 0 < max ≤ 2^32, was 0».
    final rand = Random().nextInt(0x7FFFFFFF).toRadixString(16);
    // Имя каждый раз новое, а не постоянное «avatar.jpg». Иначе браузер и
    // CDN отдавали бы старую картинку из кэша ещё долго после замены, и
    // человек решил бы, что загрузка не сработала.
    final path =
        '$uid/${prefix}_${DateTime.now().millisecondsSinceEpoch}_$rand.$ext';
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

    try {
      await supabase.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return supabase.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      if (e.toString().contains('Bucket not found')) {
        throw Failure(missingBucket);
      }
      throw mapError(e, fallback: 'Не удалось загрузить фото');
    }
  }
}
