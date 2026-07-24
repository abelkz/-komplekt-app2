import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Результат геокодирования: точка и как её понял сервис.
class GeoResult {
  const GeoResult({required this.lat, required this.lng, required this.label});
  final double lat;
  final double lng;
  final String label;
}

/// Превращает адрес в координаты через Nominatim (OpenStreetMap).
///
/// Бесплатно и без ключа. Это только подсказка: точную точку поставщик
/// всё равно ставит булавкой на карте. Поиск ограничен Казахстаном.
class GeocodingService {
  const GeocodingService();

  Future<GeoResult?> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'countrycodes': 'kz',
      'limit': '1',
      'accept-language': 'ru',
    });

    try {
      final res = await http.get(uri, headers: {
        // Nominatim просит опознавать приложение
        'User-Agent': 'KomplektApp/1.0 (kz.komplekt.app)',
      }).timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as List;
      if (data.isEmpty) return null;

      final first = data.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lng == null) return null;

      return GeoResult(
        lat: lat,
        lng: lng,
        label: first['display_name']?.toString() ?? q,
      );
    } catch (_) {
      // Сети нет или сервис недоступен — вернём null, точку поставят вручную
      return null;
    }
  }
}

final geocodingServiceProvider = Provider((ref) => const GeocodingService());
