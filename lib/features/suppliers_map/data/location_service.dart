import 'package:geolocator/geolocator.dart';

import '../../../core/config/env.dart';

/// Координаты пользователя (или дефолт — центр Астаны из .env).
class UserLocation {
  const UserLocation(this.lat, this.lng, {this.isDefault = false});
  final double lat;
  final double lng;
  final bool isDefault;
}

/// Получение геолокации с аккуратной обработкой отказов.
class LocationService {
  const LocationService();

  Future<UserLocation> current() async {
    final fallback =
        UserLocation(Env.defaultLat, Env.defaultLng, isDefault: true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) return fallback;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return fallback;
      }

      final pos = await Geolocator.getCurrentPosition(
     desiredAccuracy: LocationAccuracy.medium,
      );
      return UserLocation(pos.latitude, pos.longitude);
    } catch (_) {
      return fallback; // молча откатываемся к центру города
    }
  }
}
