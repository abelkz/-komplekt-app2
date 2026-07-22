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

  bool get isSupplier => role == 'supplier' || role == 'admin';
  bool get isApproved => status == 'approved' || role == 'admin';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  String get initials {
    final n = fullName.trim();
    return n.isEmpty ? 'Г' : n[0].toUpperCase();
  }

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'].toString(),
        fullName: m['full_name'] as String? ?? '',
        company: m['company'] as String? ?? '',
        phone: m['phone'] as String?,
        city: m['city'] as String? ?? 'Астана',
        role: m['role'] as String? ?? 'buyer',
        status: m['status'] as String? ?? 'approved',
        notifyEnabled: m['notify_price_drops'] as bool? ?? true,
        notifyThreshold: (m['notify_threshold'] as num?)?.toInt() ?? 1,
        avatarUrl: m['avatar_url'] as String?,
      );
}
