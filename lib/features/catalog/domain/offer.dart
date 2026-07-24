/// Предложение поставщика на товар (таблица offers + join suppliers).
/// Ядро сравнения цен: у одного товара — несколько предложений.
class Offer {
  const Offer({
    required this.price,
    required this.inStock,
    this.id,
    this.supplierId,
    this.supplierName = '',
    this.city = '',
    this.phone,
    this.whatsapp,
    this.website,
    this.priceUpdatedAt,
    this.prevPrice,
    this.supplierVerified = false,
    this.supplierPro = false,
    this.promotedUntil,
  });

  final String? id;
  final double price;
  final bool inStock;
  final String? supplierId;
  final String supplierName;
  final String city;
  final String? phone;
  final String? whatsapp;
  final String? website;
  final DateTime? priceUpdatedAt;

  /// Цена до последнего изменения — по ней показываем ▼/▲ на карточке.
  /// Заполняется триггером в базе (миграция 0012).
  final double? prevPrice;

  /// Поставщик проверен администратором (документы компании).
  /// Значок не продаётся: он утверждает факт проверки, а не факт оплаты.
  final bool supplierVerified;

  /// Компания на платном тарифе
  final bool supplierPro;

  /// До какого момента товар продвигается в списках.
  /// На порядок в шкале цен внутри карточки НЕ влияет — там только цена.
  final DateTime? promotedUntil;

  bool get isPromoted =>
      promotedUntil != null && promotedUntil!.isAfter(DateTime.now());

  /// Насколько изменилась цена, в процентах. Отрицательное — подешевело.
  /// null, если прежней цены нет или она не изменилась.
  int? get changePercent {
    final prev = prevPrice;
    if (prev == null || prev <= 0 || prev == price) return null;
    return ((price - prev) / prev * 100).round();
  }

  factory Offer.fromMap(Map<String, dynamic> m) {
    // suppliers может прийти как вложенный объект (PostgREST embedding)
    final supplier = m['suppliers'];
    final sup = supplier is Map<String, dynamic> ? supplier : const {};
    return Offer(
      id: m['id']?.toString(),
      price: (m['price'] as num?)?.toDouble() ?? 0,
      inStock: m['in_stock'] as bool? ?? true,
      supplierId: m['supplier_id']?.toString(),
      supplierName: sup['name'] as String? ?? '',
      city: sup['city'] as String? ?? '',
      phone: sup['phone'] as String?,
      whatsapp: sup['whatsapp'] as String?,
      website: sup['website'] as String?,
      priceUpdatedAt: m['price_updated_at'] != null
          ? DateTime.tryParse(m['price_updated_at'].toString())
          : null,
      prevPrice: (m['prev_price'] as num?)?.toDouble(),
      supplierVerified: sup['verified'] as bool? ?? false,
      // тариф считается действующим, только пока оплачен срок
      supplierPro: (sup['plan'] == 'pro') &&
          (sup['plan_until'] == null ||
              (DateTime.tryParse(sup['plan_until'].toString())
                      ?.isAfter(DateTime.now()) ??
                  false)),
      promotedUntil: m['promoted_until'] != null
          ? DateTime.tryParse(m['promoted_until'].toString())
          : null,
    );
  }
}
