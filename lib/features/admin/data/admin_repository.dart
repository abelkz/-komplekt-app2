import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../auth/domain/app_user.dart';

/// Заявка на платный тариф вместе с профилем заявителя.
class SubRequest {
  const SubRequest({
    required this.id,
    required this.userId,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.who,
    this.planUntil,
    this.planActive = false,
  });

  final int id;
  final String userId;
  final String kind; // client | supplier
  final String status; // new | contacted | paid | declined
  final DateTime createdAt;

  /// Профиль заявителя — может не подтянуться, если строку удалили
  final AppUser? who;

  /// Действующий тариф: у клиента из профиля, у поставщика — из компании
  final DateTime? planUntil;
  final bool planActive;

  bool get isNew => status == 'new';
  bool get forSupplier => kind == 'supplier';
}

/// Всё, что администратор делает с заявками. Права проверяет база:
/// без role = 'admin' политики просто ничего не отдадут.
class AdminRepository {
  const AdminRepository();

  /// Заявки поставщиков и действующие компании.
  Future<List<AppUser>> suppliers() async {
    try {
      final rows = await supabase
          .from('profiles')
          .select()
          .eq('role', 'supplier')
          .order('created_at', ascending: false);
      return rows.map<AppUser>((m) => AppUser.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить заявки поставщиков');
    }
  }

  Future<void> setSupplierStatus(String profileId, String status) async {
    try {
      await supabase
          .from('profiles')
          .update({'status': status}).eq('id', profileId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось изменить статус');
    }
  }

  /// Заявки на тариф. Профили и компании подтягиваем отдельно —
  /// внешнего ключа на profiles у таблицы нет.
  Future<List<SubRequest>> subscriptions() async {
    try {
      final rows = await supabase
          .from('subscription_requests')
          .select('id,user_id,kind,status,created_at')
          .order('created_at', ascending: false);
      if (rows.isEmpty) return const [];

      final ids = {for (final r in rows) r['user_id'] as String}.toList();

      final profiles = await supabase.from('profiles').select().inFilter('id', ids);
      final byId = {
        for (final p in profiles) p['id'].toString(): AppUser.fromMap(p)
      };

      final companies = await supabase
          .from('suppliers')
          .select('id,owner_id,plan,plan_until')
          .inFilter('owner_id', ids);
      final byOwner = <String, Map<String, dynamic>>{};
      for (final c in companies) {
        byOwner.putIfAbsent(c['owner_id'].toString(), () => c);
      }

      return rows.map<SubRequest>((r) {
        final uid = r['user_id'] as String;
        final kind = r['kind'] as String? ?? 'client';
        final me = byId[uid];
        final company = byOwner[uid];

        // Скобки обязательны: без них `as String?` внутри тернарного
        // оператора читается как начало ещё одного условия
        final plan =
            kind == 'supplier' ? (company?['plan'] as String?) : me?.plan;
        final until = kind == 'supplier'
            ? DateTime.tryParse(company?['plan_until'] as String? ?? '')
            : me?.planUntil;

        return SubRequest(
          id: (r['id'] as num).toInt(),
          userId: uid,
          kind: kind,
          status: r['status'] as String? ?? 'new',
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          who: me,
          planUntil: until,
          planActive: plan == 'pro' &&
              (until == null || until.isAfter(DateTime.now())),
        );
      }).toList();
    } catch (e) {
      // Таблицы может не быть, если миграция 0015 не применена
      if (e.toString().contains('subscription_requests')) {
        throw const Failure('Таблица заявок ещё не создана — примените миграцию 0015');
      }
      throw mapError(e, fallback: 'Не удалось загрузить заявки на тариф');
    }
  }

  /// Включает оплаченный тариф и помечает заявку. Возвращает описание —
  /// его же показываем в приложении, чтобы было видно, что именно включено.
  Future<String> activate(int requestId, int months) async {
    try {
      final res = await supabase.rpc('admin_activate_request',
          params: {'p_request': requestId, 'p_months': months});
      return res as String? ?? 'Тариф включён';
    } catch (e) {
      if (e.toString().contains('admin_activate_request')) {
        throw const Failure('Функция ещё не создана — примените миграцию 0017');
      }
      throw mapError(e, fallback: 'Не удалось включить тариф');
    }
  }

  Future<void> setRequestStatus(int requestId, String status) async {
    try {
      await supabase
          .from('subscription_requests')
          .update({'status': status}).eq('id', requestId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось изменить статус заявки');
    }
  }
}
