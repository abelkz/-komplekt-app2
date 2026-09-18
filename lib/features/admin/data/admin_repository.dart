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
    this.boostDays = 0,
    this.boostQty = 0,
  });

  final int id;
  final String userId;
  final String kind; // client | supplier | boost
  final String status; // new | contacted | paid | declined
  final DateTime createdAt;

  /// Профиль заявителя — может не подтянуться, если строку удалили
  final AppUser? who;

  /// Действующий тариф: у клиента из профиля, у поставщика — из компании
  final DateTime? planUntil;
  final bool planActive;

  /// Для заявок на Буст: срок подъёма и сколько штук
  final int boostDays;
  final int boostQty;

  bool get isNew => status == 'new';
  bool get forSupplier => kind == 'supplier';
}

/// Жалоба на отзыв (таблица content_reports, миграция 0025).
class ContentReport {
  const ContentReport({
    required this.id,
    required this.target,
    required this.reviewId,
    required this.status,
    required this.createdAt,
    this.reviewText,
    this.reporterName,
  });

  final int id;

  /// `product_review` или `supplier_review` — в какой таблице искать отзыв.
  final String target;

  /// Текстом, потому что у отзывов о товарах id типа uuid, а о поставщиках —
  /// bigint (см. миграцию 0025).
  final String reviewId;

  final String status; // new | reviewed | removed | rejected
  final DateTime createdAt;

  /// Текст отзыва, на который пожаловались. Может не подтянуться, если отзыв
  /// уже удалён — тогда жалобу всё равно показываем, просто без текста.
  final String? reviewText;

  final String? reporterName;

  bool get isNew => status == 'new';
  bool get onSupplier => target == 'supplier_review';
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

  /// Заявки на покупку Буста вместе с профилем заявителя.
  Future<List<SubRequest>> boostOrders() async {
    try {
      final rows = await supabase
          .from('boost_orders')
          .select('id,user_id,days,qty,status,created_at')
          .order('created_at', ascending: false);
      if (rows.isEmpty) return const [];

      final ids = {for (final r in rows) r['user_id'] as String}.toList();
      final profiles = await supabase.from('profiles').select().inFilter('id', ids);
      final byId = {
        for (final p in profiles) p['id'].toString(): AppUser.fromMap(p)
      };

      return rows.map<SubRequest>((r) {
        final days = (r['days'] as num).toInt();
        final qty = (r['qty'] as num).toInt();
        return SubRequest(
          id: (r['id'] as num).toInt(),
          userId: r['user_id'] as String,
          kind: 'boost',
          status: r['status'] as String? ?? 'new',
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          who: byId[r['user_id']],
          boostDays: days,
          boostQty: qty,
        );
      }).toList();
    } catch (e) {
      if (e.toString().contains('boost_orders')) {
        throw const Failure('Таблица Буста ещё не создана — примените миграцию 0020');
      }
      throw mapError(e, fallback: 'Не удалось загрузить заявки на Буст');
    }
  }

  /// Подтвердить оплату Буста: начислить кредиты поставщику.
  Future<int> grantBoost(int orderId) async {
    try {
      final res =
          await supabase.rpc('admin_grant_boost', params: {'p_order': orderId});
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      if (e.toString().contains('admin_grant_boost')) {
        throw const Failure('Функция ещё не создана — примените миграцию 0021');
      }
      throw mapError(e, fallback: 'Не удалось начислить Буст');
    }
  }

  Future<void> setBoostStatus(int orderId, String status) async {
    try {
      await supabase
          .from('boost_orders')
          .update({'status': status}).eq('id', orderId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось изменить статус');
    }
  }

  /// Жалобы на отзывы — самые свежие сверху.
  Future<List<ContentReport>> reports() async {
    try {
      final rows = await supabase
          .from('content_reports')
          .select('id,target,review_id,reporter_id,status,created_at')
          .order('created_at', ascending: false)
          .limit(200);
      if (rows.isEmpty) return const [];

      // Тексты отзывов и имена подтягиваем отдельными запросами: внешнего
      // ключа у жалобы нет, потому что она указывает на одну из двух таблиц.
      final texts = <String, String>{};
      await _fillReviewTexts(rows, 'product_review', 'reviews', texts);
      await _fillReviewTexts(rows, 'supplier_review', 'supplier_reviews', texts);

      final names = <String, String>{};
      final reporterIds = {
        for (final r in rows)
          if (r['reporter_id'] != null) r['reporter_id'].toString(),
      }.toList();
      if (reporterIds.isNotEmpty) {
        try {
          final profiles = await supabase
              .from('profiles')
              .select('id,full_name')
              .inFilter('id', reporterIds);
          for (final p in profiles) {
            names[p['id'].toString()] = (p['full_name'] as String?) ?? '';
          }
        } catch (_) {
          // Имя не критично — жалобу нужно показать в любом случае.
        }
      }

      return rows.map<ContentReport>((r) {
        final target = r['target'] as String? ?? 'product_review';
        final reviewId = r['review_id'].toString();
        final reporter = r['reporter_id']?.toString();
        return ContentReport(
          id: (r['id'] as num).toInt(),
          target: target,
          reviewId: reviewId,
          status: r['status'] as String? ?? 'new',
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          reviewText: texts['$target:$reviewId'],
          reporterName: reporter == null ? null : names[reporter],
        );
      }).toList();
    } catch (e) {
      if (e.toString().contains('content_reports')) {
        throw const Failure(
            'Таблица жалоб ещё не создана — примените миграцию 0025');
      }
      throw mapError(e, fallback: 'Не удалось загрузить жалобы');
    }
  }

  /// Подтягивает тексты отзывов одной таблицы в общий словарь.
  /// Ключ — «цель:id», потому что идентификаторы из разных таблиц могут
  /// совпасть: там uuid, тут просто числа.
  Future<void> _fillReviewTexts(
    List<dynamic> rows,
    String target,
    String table,
    Map<String, String> into,
  ) async {
    final ids = [
      for (final r in rows)
        if (r['target'] == target) r['review_id'].toString(),
    ];
    if (ids.isEmpty) return;
    try {
      final found =
          await supabase.from(table).select('id,text').inFilter('id', ids);
      for (final f in found) {
        into['$target:${f['id']}'] = (f['text'] as String?) ?? '';
      }
    } catch (_) {
      // Отзыв мог быть уже удалён — не повод ронять весь список.
    }
  }

  Future<void> setReportStatus(int reportId, String status) async {
    try {
      await supabase
          .from('content_reports')
          .update({'status': status}).eq('id', reportId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось изменить статус жалобы');
    }
  }

  /// Удаляет отзыв и закрывает все жалобы на него. Через обычный запрос
  /// это невозможно: политики дают право удалять только автору.
  Future<void> deleteReview(ContentReport report) async {
    try {
      await supabase.rpc('admin_delete_review', params: {
        'p_target': report.target,
        'p_review_id': report.reviewId,
      });
    } catch (e) {
      if (e.toString().contains('admin_delete_review')) {
        throw const Failure(
            'Функция ещё не создана — примените миграцию 0025');
      }
      throw mapError(e, fallback: 'Не удалось удалить отзыв');
    }
  }
}
