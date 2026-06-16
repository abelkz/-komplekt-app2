/// Поставщик (таблица suppliers). Используется на карте и в витрине продавца.
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.city = '',
    this.address,
    this.phone,
    this.whatsapp,
    this.website,
    this.description,
    this.logoUrl,
    this.rating = 0,
    this.lat,
    this.lng,
    this.distanceM,
  });

  final String id;
  final String name;
  final String city;
  final String? address;
  final String? phone;
  final String? whatsapp;
  final String? website;
  final String? description;
  final String? logoUrl;
  final double rating;
  final double? lat;
  final double? lng;

  /// Расстояние до пользователя в метрах (заполняется RPC nearby_suppliers).
  final double? distanceM;

  bool get hasLocation => lat != null && lng != null;

  /// "1,2 км" / "350 м"
  String? get distanceLabel {
    final d = distanceM;
    if (d == null) return null;
    if (d < 1000) return '${d.round()} м';
    return '${(d / 1000).toStringAsFixed(1)} км';
  }

  factory Supplier.fromMap(Map<String, dynamic> m) => Supplier(
        id: m['id'].toString(),
        name: m['name'] as String? ?? '',
        city: m['city'] as String? ?? '',
        address: m['address'] as String?,
        phone: m['phone'] as String?,
        whatsapp: m['whatsapp'] as String?,
        website: m['website'] as String?,
        description: m['description'] as String?,
        logoUrl: m['logo_url'] as String?,
        rating: (m['rating'] as num?)?.toDouble() ?? 0,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        distanceM: (m['distance_m'] as num?)?.toDouble(),
      );
}
