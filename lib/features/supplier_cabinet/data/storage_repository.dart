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

    final rand = Random().nextInt(1 << 32).toRadixString(16);
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
      throw mapError(e, fallback: 'Не удалось загрузить фото');
    }
  }
}
