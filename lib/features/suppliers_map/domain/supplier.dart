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
    this.reviewsCount = 0,
    this.sinceYear,
    this.about,
    this.lat,
    this.lng,
    this.distanceM,
    this.verified = false,
    this.plan = 'free',
    this.planUntil,
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
  final int reviewsCount;

  /// Год начала работы компании — для «N лет на рынке»
  final int? sinceYear;
  final String? about;

  /// Сколько лет на рынке (по году начала работы)
  int? get yearsOnMarket {
    final y = sinceYear;
    if (y == null || y < 1900) return null;
    final n = DateTime.now().year - y;
    return n < 0 ? null : n;
  }

  /// Проверенная компания — администратор посмотрел документы.
  /// Значок не продаётся: он про проверку, а не про оплату.
  final bool verified;

  /// Тариф: free или pro
  final String plan;

  /// До какого момента оплачен тариф
  final DateTime? planUntil;

  /// Платный тариф действует прямо сейчас
  bool get isPro =>
      plan == 'pro' && (planUntil == null || planUntil!.isAfter(DateTime.now()));

  final double? lat;
  final double? lng;

  /// Расстояние до пользователя в метрах (заполняется RPC nearby_suppliers).
  final double? distanceM;

  bool get hasLocation => lat != null && lng != null;

  Supplier copyWith({double? distanceM, String? address, double? lat, double? lng}) =>
      Supplier(
        id: id,
        name: name,
        city: city,
        address: address ?? this.address,
        phone: phone,
        whatsapp: whatsapp,
        website: website,
        description: description,
        logoUrl: logoUrl,
        rating: rating,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        distanceM: distanceM ?? this.distanceM,
        verified: verified,
        plan: plan,
        planUntil: planUntil,
      );

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
        reviewsCount: (m['reviews_count'] as num?)?.toInt() ?? 0,
        sinceYear: (m['since_year'] as num?)?.toInt(),
        about: m['about'] as String?,
        verified: m['verified'] as bool? ?? false,
        plan: m['plan'] as String? ?? 'free',
        planUntil: m['plan_until'] != null
            ? DateTime.tryParse(m['plan_until'].toString())
            : null,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        distanceM: (m['distance_m'] as num?)?.toDouble(),
      );
}
