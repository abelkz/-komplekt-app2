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

/// Сводка по приложению (RPC `admin_overview`, миграция 0030).
class AdminOverview {
  const AdminOverview({
    required this.usersTotal,
    required this.usersNew,
    required this.suppliersTotal,
    required this.suppliersPending,
    required this.productsTotal,
    required this.offersTotal,
    required this.searches,
    required this.productViews,
    required this.categoryOpens,
    required this.contacts,
    required this.favoritesTotal,
    required this.paidTotal,
  });

  final int usersTotal;
  final int usersNew;
  final int suppliersTotal;
  final int suppliersPending;
  final int productsTotal;
  final int offersTotal;
  final int searches;
  final int productViews;
  final int categoryOpens;
  final int contacts;
  final int favoritesTotal;
  final double paidTotal;

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;

  factory AdminOverview.fromMap(Map<String, dynamic> m) => AdminOverview(
        usersTotal: _i(m['users_total']),
        usersNew: _i(m['users_new']),
        suppliersTotal: _i(m['suppliers_total']),
        suppliersPending: _i(m['suppliers_pending']),
        productsTotal: _i(m['products_total']),
        offersTotal: _i(m['offers_total']),
        searches: _i(m['searches']),
        productViews: _i(m['product_views']),
        categoryOpens: _i(m['category_opens']),
        contacts: _i(m['contacts']),
        favoritesTotal: _i(m['favorites_total']),
        // numeric приезжает из PostgREST строкой, а не числом
        paidTotal: double.tryParse('${m['paid_total'] ?? 0}') ?? 0,
      );
}

/// Строка списка «что искали» / «какие категории открывали».
class CountedRow {
  const CountedRow({required this.label, required this.n, this.hint});
  final String label;
  final int n;

  /// Второстепенная подпись: у категории — её slug.
  final String? hint;
}

/// Поставщик с показателями (RPC `admin_suppliers`, миграция 0030).
class SupplierRow {
  const SupplierRow({
    required this.id,
    required this.name,
    required this.city,
    required this.products,
    required this.offers,
    required this.views,
    required this.contacts,
    this.plan,
    this.planUntil,
    this.verified = false,
    this.status,
    this.lastPriceAt,
    this.blockedUntil,
    this.blockReason,
  });

  final String id;
  final String name;
  final String city;
  final int products;
  final int offers;
  final int views;
  final int contacts;
  final String? plan;
  final DateTime? planUntil;
  final bool verified;
  final String? status;

  /// Когда последний раз трогали прайс. Мёртвый прайс хуже отсутствующего:
  /// покупатель звонит по цене, которой уже нет.
  final DateTime? lastPriceAt;

  /// До какого момента компания скрыта (миграция 0032). null — не
  /// заблокирована. Далёкая дата — бессрочно: в базе там `infinity`.
  final DateTime? blockedUntil;

  /// За что заблокирована. Показываем и админу, и самому поставщику:
  /// человек должен понимать причину, иначе просто уйдёт.
  final String? blockReason;

  bool get isPro =>
      plan == 'pro' && (planUntil == null || planUntil!.isAfter(DateTime.now()));

  /// Заблокирована прямо сейчас. Прошедший срок снимает блокировку сам,
  /// поэтому проверяем дату, а не просто её наличие.
  bool get isBlocked =>
      blockedUntil != null && blockedUntil!.isAfter(DateTime.now());

  /// Бессрочная блокировка. В базе это `infinity`, который приезжает сюда
  /// либо как неразобранная дата, либо как год из далёкого будущего —
  /// показывать «до 31.12.294276» нельзя, это выглядит как поломка.
  bool get blockedForever =>
      isBlocked && blockedUntil!.year > DateTime.now().year + 50;

  factory SupplierRow.fromMap(Map<String, dynamic> m) => SupplierRow(
        id: m['supplier_id'].toString(),
        name: m['name'] as String? ?? '',
        city: m['city'] as String? ?? '',
        products: (m['products'] as num?)?.toInt() ?? 0,
        offers: (m['offers'] as num?)?.toInt() ?? 0,
        views: (m['views'] as num?)?.toInt() ?? 0,
        contacts: (m['contacts'] as num?)?.toInt() ?? 0,
        plan: m['plan'] as String?,
        planUntil: m['plan_until'] == null
            ? null
            : DateTime.tryParse(m['plan_until'].toString()),
        verified: m['verified'] as bool? ?? false,
        status: m['status'] as String?,
        lastPriceAt: m['last_price_at'] == null
            ? null
            : DateTime.tryParse(m['last_price_at'].toString()),
        // 'infinity' из Postgres DateTime.tryParse не разберёт и вернёт null —
        // бессрочная блокировка выглядела бы как её отсутствие. Подменяем
        // такой случай далёкой датой: она и означает «бессрочно».
        blockedUntil: _until(m['blocked_until']),
        blockReason: m['block_reason'] as String?,
      );

  static DateTime? _until(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s == 'infinity') return DateTime(9999);
    return DateTime.tryParse(s);
  }
}

/// Всё, что администратор делает с заявками. Права проверяет база:
/// без role = 'admin' политики просто ничего не отдадут.
class AdminRepository {
  const AdminRepository();

  // ─────────────────────────── Статистика ───────────────────────────
  //
  // Считает база (миграция 0030). Здесь только разбор ответа: агрегировать
  // на клиенте нельзя — RLS отдаёт строки, и ради одного числа пришлось бы
  // тянуть в браузер всю таблицу профилей вместе с персональными данными.

  /// Сводка за последние [days] дней.
  Future<AdminOverview> overview({int days = 30}) async {
    try {
      final rows = await supabase.rpc('admin_overview', params: {'p_days': days});
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) throw const Failure('База не вернула сводку');
      return AdminOverview.fromMap(list.first);
    } catch (e) {
      if (e is Failure) rethrow;
      throw mapError(e, fallback: 'Не удалось загрузить сводку');
    }
  }

  /// Что искали. Пустой список — нормальное состояние: значит за период
  /// никто не искал, а не «сломалось».
  Future<List<CountedRow>> topSearches({int days = 30, int limit = 20}) async {
    try {
      final rows = await supabase.rpc('admin_top_searches',
          params: {'p_days': days, 'p_limit': limit});
      return [
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          CountedRow(
            label: r['query'] as String? ?? '',
            n: (r['n'] as num?)?.toInt() ?? 0,
          ),
      ];
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить поисковые запросы');
    }
  }

  /// Какие категории открывали, а какие лежат мёртвым грузом.
  Future<List<CountedRow>> topCategories({int days = 30, int limit = 20}) async {
    try {
      final rows = await supabase.rpc('admin_top_categories',
          params: {'p_days': days, 'p_limit': limit});
      return [
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          CountedRow(
            label: r['name'] as String? ?? '',
            n: (r['n'] as num?)?.toInt() ?? 0,
            hint: r['slug'] as String?,
          ),
      ];
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить категории');
    }
  }

  // ──────────────── Блокировка и удаление компании ────────────────
  //
  // Всё решает база (миграция 0032): функции security definer, каждая сама
  // проверяет админа. Отсюда — только вызов и понятный текст ошибки.

  /// Скрыть компанию из каталога. [days] = null — бессрочно.
  /// Возвращает дату, до которой скрыта.
  Future<DateTime?> blockSupplier(String supplierId,
      {int? days, String? reason}) async {
    try {
      final res = await supabase.rpc('admin_block_supplier', params: {
        'p_supplier': int.tryParse(supplierId) ?? supplierId,
        'p_days': days,
        'p_reason': reason,
      });
      return res == null ? null : DateTime.tryParse(res.toString());
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось заблокировать компанию');
    }
  }

  Future<void> unblockSupplier(String supplierId) async {
    try {
      await supabase.rpc('admin_unblock_supplier',
          params: {'p_supplier': int.tryParse(supplierId) ?? supplierId});
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось снять блокировку');
    }
  }

  /// Удалить компанию. Возвращает, сколько цен при этом снесено.
  /// Товары остаются: карточка общая, на неё ссылаются чужие цены.
  Future<int> deleteSupplier(String supplierId) async {
    try {
      final res = await supabase.rpc('admin_delete_supplier',
          params: {'p_supplier': int.tryParse(supplierId) ?? supplierId});
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось удалить компанию');
    }
  }

  /// Поставщики с показателями за период.
  Future<List<SupplierRow>> supplierStats({int days = 30}) async {
    try {
      final rows =
          await supabase.rpc('admin_suppliers', params: {'p_days': days});
      return [
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          SupplierRow.fromMap(r),
      ];
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить поставщиков');
    }
  }

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
