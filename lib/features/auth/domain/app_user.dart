/// Профиль пользователя приложения (таблица users).
class AppUser {
  const AppUser({
    required this.id,
    this.fullName = '',
    this.company = '',
    this.phone,
    this.city = 'Астана',
    this.role = 'buyer',
    this.status = 'approved',
    this.notifyEnabled = true,
    this.notifyThreshold = 1,
    this.avatarUrl,
    this.plan = 'free',
    this.planUntil,
  });

  final String id;
  final String fullName;

  /// Название компании поставщика — им товар подписан в каталоге
  final String company;
  final String? phone;
  final String city;
  final String role; // buyer | supplier | admin
  final String status; // pending | approved | rejected
  final bool notifyEnabled; // уведомления о снижении цены
  final int notifyThreshold; // минимальный % снижения для уведомления
  final String? avatarUrl;

  /// Тариф самого пользователя: free | pro. У поставщика тариф компании
  /// живёт отдельно, в suppliers.plan — он про продвижение и значок.
  final String plan;
  final DateTime? planUntil;

  /// Оплаченный «КОМПЛЕКТ Про» действует. Пустая дата — бессрочно.
  bool get isPro =>
      plan == 'pro' &&
      (planUntil == null || planUntil!.isAfter(DateTime.now()));

  bool get isSupplier => role == 'supplier' || role == 'admin';
  bool get isApproved => status == 'approved' || role == 'admin';
  bool get isRejected => status == 'rejected';

  /// Всё, что не «одобрен» и не «отклонён», считаем ожиданием проверки:
  /// неизвестный статус не должен открывать кабинет.
  bool get isPending => !isApproved && !isRejected;

  String get initials {
    final n = fullName.trim();
    return n.isEmpty ? 'Г' : n[0].toUpperCase();
  }

  factory AppUser.fromMap(Map<String, dynamic> m) {
    final role = m['role'] as String? ?? 'buyer';
    return AppUser(
      id: m['id'].toString(),
      fullName: m['full_name'] as String? ?? '',
      company: m['company'] as String? ?? '',
      phone: m['phone'] as String?,
      city: m['city'] as String? ?? 'Астана',
      role: role,
      // покупателя никто не модерирует, а вот поставщик без статуса —
      // это заявка, а не одобренная компания
      status: m['status'] as String? ??
          (role == 'supplier' ? 'pending' : 'approved'),
      notifyEnabled: m['notify_price_drops'] as bool? ?? true,
      notifyThreshold: (m['notify_threshold'] as num?)?.toInt() ?? 1,
      avatarUrl: m['avatar_url'] as String?,
      plan: m['plan'] as String? ?? 'free',
      planUntil: DateTime.tryParse(m['plan_until'] as String? ?? ''),
    );
  }
}
