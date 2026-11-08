import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../catalog/domain/product.dart';
import '../../suppliers_map/domain/supplier.dart';
import 'sku_match.dart';

/// Ошибка с настоящим текстом от базы.
///
/// В кабинете поставщика общее «не удалось сохранить» бесполезно: причина
/// почти всегда конкретная — не хватило прав, нарушено ограничение, нет
/// колонки. Показываем её человеку и себе.
Failure _dbFail(Object e, String what) {
  if (e is PostgrestException) {
    final code = e.code;
    if (code == '42501') {
      return Failure('$what: база не опознала пользователя. '
          'Выйдите и войдите заново — скорее всего истекла сессия.');
    }
    final detail = [e.message, if (code != null) 'код $code'].join(' · ');
    return Failure('$what: $detail');
  }
  return mapError(e, fallback: what);
}

/// Отказ из-за конкретной строки прайса, а не из-за файла или настроек
/// базы.
///
/// Разбирать пачку по одной строке стоит только в этом случае. Если база
/// отвечает «нет такой колонки» или «нет прав», то же самое она ответит
/// и на каждую строку по отдельности — перебор 2000 строк даст пару тысяч
/// бесполезных запросов и тот же отказ в конце. Такие ошибки честнее
/// показать целиком и сразу.
bool _isRowLevel(Object e) {
  if (e is Failure) return true; // наши собственные проверки по строке
  if (e is! PostgrestException) return false;
  const rowCodes = {
    '23505', // нарушена уникальность — карточка с таким артикулом уже есть
    '23503', // нет такой категории или поставщика
    '23514', // значение не прошло проверку
    '22P02', // не число там, где ждали число
    '22003', // число не влезает в колонку
    '22001', // строка длиннее колонки
  };
  return rowCodes.contains(e.code);
}

/// Импортируемая строка прайса (после сопоставления колонок).
class PriceRow {
  PriceRow({
    required this.name,
    required this.price,
    this.sku,
    this.unit = 'шт',
    this.imageUrl,
    this.stockQty,
    this.leadTimeDays,
  });
  final String name;
  final double price;
  final String? sku;
  final String unit;
  final String? imageUrl;

  /// Остаток и срок поставки из прайса (миграция 0029). null — колонки
  /// в файле не было; тогда в базе остаётся «не указано», а не ноль.
  final double? stockQty;
  final int? leadTimeDays;
}

/// Итог импорта прайса.
///
/// Поставщику важно видеть не только «загружено N», а сколько его строк
/// легло на УЖЕ СУЩЕСТВУЮЩИЕ карточки каталога: в этом весь смысл общего
/// каталога, и это же лучший довод в разговоре с ним.
class ImportResult {
  const ImportResult({
    required this.created,
    required this.matched,
    required this.failed,
    this.firstError,
  });

  static const empty = ImportResult(created: 0, matched: 0, failed: []);

  /// Новых карточек каталога — товара в каталоге не было
  final int created;

  /// Цен, добавленных к карточкам, которые в каталоге уже были
  final int matched;

  /// Названия строк, которые загрузить не удалось
  final List<String> failed;

  /// Причина первой неудачной строки — без неё «не вышло 40» бесполезно
  final String? firstError;

  int get total => created + matched;
}

/// Что доступно поставщику для подъёма в топ прямо сейчас.
class BoostStatus {
  const BoostStatus({
    required this.isPro,
    required this.freeLeft,
    required this.credits,
  });

  /// Действует ли тариф Pro (даёт бесплатные подъёмы)
  final bool isPro;

  /// Сколько бесплатных подъёмов Pro осталось в этом месяце
  final int freeLeft;

  /// Купленные кредиты Буста: срок (дней) -> сколько штук
  final Map<int, int> credits;

  bool get hasCredits => credits.values.any((c) => c > 0);
  int creditsFor(int days) => credits[days] ?? 0;

  factory BoostStatus.fromJson(Map<String, dynamic> m) {
    final list = (m['credits'] as List?) ?? const [];
    final credits = <int, int>{};
    for (final e in list) {
      final map = e as Map<String, dynamic>;
      credits[(map['days'] as num).toInt()] = (map['count'] as num).toInt();
    }
    return BoostStatus(
      isPro: m['is_pro'] as bool? ?? false,
      freeLeft: (m['free_left'] as num?)?.toInt() ?? 0,
      credits: credits,
    );
  }
}

/// Найденная в общем каталоге карточка — к ней поставщик добавляет свою цену.
class CatalogMatch {
  const CatalogMatch({
    required this.id,
    required this.name,
    this.sku,
    this.unit = 'шт',
    this.imageUrl,
    this.categorySlug,
    this.brandName,
    this.offersCount = 0,
    this.minPrice,
    this.mine = false,
  });

  final String id;
  final String name;

  /// Артикул производителя — по нему карточки и объединяются
  final String? sku;
  final String unit;
  final String? imageUrl;
  final String? categorySlug;
  final String? brandName;

  /// Сколько поставщиков уже продают этот товар
  final int offersCount;
  final double? minPrice;

  /// У меня уже есть предложение на этот товар
  final bool mine;

  factory CatalogMatch.fromMap(Map<String, dynamic> m) => CatalogMatch(
        id: m['id'].toString(),
        name: m['name'] as String? ?? '',
        sku: m['sku'] as String?,
        unit: m['unit'] as String? ?? 'шт',
        imageUrl: m['image_url'] as String?,
        categorySlug: m['category_slug'] as String?,
        brandName: m['brand_name'] as String?,
        offersCount: (m['offers_count'] as num?)?.toInt() ?? 0,
        minPrice: (m['min_price'] as num?)?.toDouble(),
        mine: m['mine'] as bool? ?? false,
      );
}

/// Статистика по товару (просмотры/контакты).
class ProductStat {
  const ProductStat(this.views, this.contacts);
  final int views;
  final int contacts;
}

/// Кабинет поставщика: компания, товары, цены, импорт, статистика.
///
/// ВАЖНО про схему живой базы: владелец записи — это `owner_id`
/// (колонки `created_by` там нет), основное фото товара лежит прямо
/// в `products.image_url`, а марка — только в отдельной таблице brands.
/// Веб-кабинет supplier.html пишет ровно так же — форматы совпадают.
class SupplierCabinetRepository {
  const SupplierCabinetRepository();

  String? get _uid => supabase.auth.currentUser?.id;

  /// Проверяет, что база сможет опознать пользователя, и при необходимости
  /// продлевает сессию.
  ///
  /// Приложение месяцами живёт вкладкой в фоне: ключ сессии протухает,
  /// автоматическое продление не срабатывает, и запись отлетает по правам
  /// (auth.uid() пустой), хотя человек по-прежнему «в аккаунте».
  Future<String> _requireSession() async {
    var session = supabase.auth.currentSession;
    if (session == null) throw const Failure('Нужно войти');
    if (session.isExpired) {
      try {
        final res = await supabase.auth.refreshSession();
        session = res.session;
      } catch (_) {
        throw const Failure('Сессия истекла — выйдите и войдите заново');
      }
      if (session == null) {
        throw const Failure('Сессия истекла — выйдите и войдите заново');
      }
    }
    return session.user.id;
  }

  /// Найти карточку компании владельца или создать её.
  Future<Supplier> ensureCompany({
    required String fallbackName,
    required String city,
    String? phone,
  }) async {
    final uid = await _requireSession();
    try {
      final existing = await supabase
          .from('suppliers')
          .select()
          .eq('owner_id', uid)
          .limit(1)
          .maybeSingle();
      if (existing != null) return Supplier.fromMap(existing);

      final created = await supabase
          .from('suppliers')
          .insert({
            'owner_id': uid,
            'name': fallbackName.isEmpty ? 'Моя компания' : fallbackName,
            'city': city,
            'phone': phone,
          })
          .select()
          .single();
      return Supplier.fromMap(created);
    } catch (e) {
      throw _dbFail(e, 'Не удалось создать карточку компании');
    }
  }

  /// Сохранить адрес и точку на карте своей компании.
  /// Пишем прямо в свою строку suppliers (owner_id = я).
  Future<void> saveLocation({
    required String address,
    required double lat,
    required double lng,
  }) async {
    final uid = await _requireSession();
    try {
      await supabase
          .from('suppliers')
          .update({
            'address': address.trim(),
            'lat': lat,
            'lng': lng,
          })
          .eq('owner_id', uid);
    } catch (e) {
      throw _dbFail(e, 'Не удалось сохранить адрес');
    }
  }

  /// Профиль компании для витрины: WhatsApp, сайт, год работы, описание.
  Future<void> saveCompanyProfile({
    String? whatsapp,
    String? website,
    int? sinceYear,
    String? about,
    String? logoUrl,
  }) async {
    final uid = await _requireSession();
    try {
      await supabase.from('suppliers').update({
        'whatsapp': _nullIfEmpty(whatsapp),
        'website': _nullIfEmpty(website),
        'since_year': sinceYear,
        'about': _nullIfEmpty(about),
        // Колонка из миграции 0031. null здесь — осознанное «убрать логотип»,
        // форма всегда присылает текущее состояние.
        'logo_url': _nullIfEmpty(logoUrl),
      }).eq('owner_id', uid);
    } catch (e) {
      throw _dbFail(e, 'Не удалось сохранить профиль компании');
    }
  }

  static String? _nullIfEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  /// Мой ассортимент — товары, на которые у меня есть предложение.
  ///
  /// Идём от предложений, а не от карточек: в общем каталоге поставщик
  /// продаёт и то, что завёл сам, и то, что до него завёл кто-то другой.
  /// Карточка одна, фото одно, а цены у каждого свои.
  Future<List<Product>> myProducts() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await supabase
          .from('offers')
          .select('id,price,prev_price,in_stock,price_updated_at,promoted_until,supplier_id,'
              'supplier_sku,'
              'products(id,name,sku,unit,color,image_url,category_slug,owner_id,'
              'brands(name),product_images(url,sort))')
          .eq('owner_id', uid)
          .order('id', ascending: false);

      final result = <Product>[];
      for (final row in rows) {
        final p = row['products'];
        if (p is! Map<String, dynamic>) continue;
        // Прикладываем к карточке только моё предложение: в кабинете
        // поставщик правит свою цену, а не чужие.
        final map = Map<String, dynamic>.from(p);
        map['offers'] = [
          {
            'id': row['id'],
            'price': row['price'],
            'prev_price': row['prev_price'],
            'in_stock': row['in_stock'],
            'price_updated_at': row['price_updated_at'],
            'supplier_id': row['supplier_id'],
            'supplier_sku': row['supplier_sku'],
            'promoted_until': row['promoted_until'],
          }
        ];
        result.add(Product.fromMap(map));
      }
      return result;
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить товары');
    }
  }

  /// Поиск по общему каталогу — чтобы поставщик не заводил дубль карточки,
  /// а добавил свою цену к существующей.
  Future<List<CatalogMatch>> searchCatalog(String query, String supplierId) async {
    if (query.trim().length < 2) return const [];
    try {
      final rows = await supabase.rpc('catalog_search', params: {
        'p_query': query.trim(),
        'p_supplier': int.tryParse(supplierId) ?? supplierId,
      });
      return (rows as List)
          .map((r) => CatalogMatch.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      // Функции ещё нет (миграция 0013) — ищем по названию напрямую
      try {
        final rows = await supabase
            .from('products')
            .select('id,name,sku,unit,image_url,category_slug,brands(name)')
            .or('name.ilike.%${query.trim()}%,sku.ilike.%${query.trim()}%')
            .limit(20);
        return rows
            .map((r) => CatalogMatch(
                  id: r['id'].toString(),
                  name: r['name'] as String? ?? '',
                  sku: r['sku'] as String?,
                  unit: r['unit'] as String? ?? 'шт',
                  imageUrl: r['image_url'] as String?,
                  categorySlug: r['category_slug'] as String?,
                  brandName: (r['brands'] is Map)
                      ? r['brands']['name'] as String?
                      : null,
                ))
            .toList();
      } catch (_) {
        return const [];
      }
    }
  }

  /// Добавить своё предложение к существующей карточке каталога.
  Future<void> addOfferToProduct({
    required String productId,
    required String supplierId,
    required double price,
    required bool inStock,
    String? supplierSku,
  }) async {
    final uid = await _requireSession();
    try {
      final existing = await supabase
          .from('offers')
          .select('id')
          .eq('product_id', productId)
          .eq('supplier_id', supplierId)
          .maybeSingle();
      if (existing != null) {
        throw const Failure('Этот товар уже есть в вашем прайсе');
      }
      await supabase.from('offers').insert({
        'product_id': productId,
        'supplier_id': supplierId,
        'owner_id': uid,
        'price': price,
        'in_stock': inStock,
        if (supplierSku != null && supplierSku.isNotEmpty)
          'supplier_sku': supplierSku,
      });
    } on Failure {
      rethrow;
    } catch (e) {
      throw _dbFail(e, 'Не удалось добавить цену');
    }
  }

  /// Добавить один товар (+ цену + фото при наличии ссылки).
  Future<void> addProduct({
    required String name,
    required String categorySlug,
    required String unit,
    required double price,
    required bool inStock,
    required String supplierId,
    String? sku,
    String? imageUrl,
    double? packQty,
    int? warrantyMonths,
    List<String> attrs = const [],
    double? stockQty,
    int? leadTimeDays,
    String? brand,
  }) async {
    final uid = await _requireSession();
    try {
      final product = await supabase
          .from('products')
          .insert({
            'name': name,
            'sku': sku,
            'unit': unit,
            'category_slug': categorySlug,
            'image_url': (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl,
            'owner_id': uid,
            'pack_qty': packQty,
            'warranty_months': warrantyMonths,
            'attrs': attrs,
          })
          .select('id')
          .single();
      final productId = product['id'];

      await supabase.from('offers').insert({
        'product_id': productId,
        'supplier_id': supplierId,
        'owner_id': uid,
        'price': price,
        'in_stock': inStock,
        'stock_qty': stockQty,
        'lead_time_days': leadTimeDays,
      });

      // Товар и цена уже вставлены. Если марка не записалась, говорить
      // «не удалось сохранить товар» нельзя: поставщик нажмёт «сохранить»
      // ещё раз и заведёт дубль. Поэтому здесь отдельное сообщение.
      try {
        await _setBrand(productId, brand);
      } catch (e) {
        throw _dbFail(e, 'Товар сохранён, но марку записать не вышло');
      }
    } on Failure {
      rethrow;
    } catch (e) {
      throw _dbFail(e, 'Не удалось сохранить товар');
    }
  }

  /// Марку ставим через RPC (миграция 0034), а не записью brand_id.
  /// Таблица brands закрыта на запись: функция сама нормализует название,
  /// найдёт уже существующую марку без учёта регистра и только потом
  /// заведёт новую — иначе «Kerama Marazzi» быстро стало бы десятком
  /// написаний, и фильтр по марке перестал бы работать.
  Future<void> _setBrand(Object productId, String? brand) async {
    await supabase.rpc('set_product_brand', params: {
      'p_product': productId,
      'p_brand': brand,
    });
  }

  /// Поднять своё предложение в топ списков на [days] дней.
  ///
  /// Доступно только на тарифе Pro — проверку делает база. На порядок
  /// в шкале цен внутри карточки товара это не влияет: там всегда
  /// первым идёт тот, у кого дешевле.
  Future<DateTime?> promoteOffer(String offerId, {int days = 3}) async {
    await _requireSession();
    try {
      final res = await supabase.rpc('promote_offer', params: {
        'p_offer': int.tryParse(offerId) ?? offerId,
        'p_days': days,
      });
      return res == null ? null : DateTime.tryParse(res.toString());
    } catch (e) {
      if (e.toString().contains('promote_offer')) {
        throw const Failure('Продвижение ещё не настроено на сервере');
      }
      throw _dbFail(e, 'Не удалось продвинуть товар');
    }
  }

  /// Сводка по продвижению: остаток бесплатных подъёмов Pro и купленные
  /// кредиты Буста по срокам.
  Future<BoostStatus> boostStatus() async {
    await _requireSession();
    try {
      final res = await supabase.rpc('my_boost_status');
      return BoostStatus.fromJson(res as Map<String, dynamic>);
    } catch (e) {
      if (e.toString().contains('my_boost_status')) {
        // Функции ещё нет (миграции 0020/0021) — считаем, что подъёмов нет
        return const BoostStatus(isPro: false, freeLeft: 0, credits: {});
      }
      throw _dbFail(e, 'Не удалось получить статус продвижения');
    }
  }

  /// Заявка на покупку Буста: qty подъёмов по days дней.
  Future<void> orderBoost({required int days, required int qty}) async {
    await _requireSession();
    try {
      await supabase.rpc('order_boost', params: {'p_days': days, 'p_qty': qty});
    } catch (e) {
      if (e.toString().contains('order_boost')) {
        throw const Failure('Покупка Буста ещё не настроена на сервере');
      }
      throw _dbFail(e, 'Не удалось оформить заявку на Буст');
    }
  }

  /// Изменить карточку товара: название, артикул, единицу, категорию, фото,
  /// а также данные из миграции 0029 — фасовку, гарантию и характеристики.
  /// Цена живёт отдельно, в предложении — её меняет [saveOffer].
  Future<void> updateProduct({
    required String productId,
    required String name,
    required String categorySlug,
    required String unit,
    String? sku,
    String? imageUrl,
    double? packQty,
    int? warrantyMonths,
    List<String> attrs = const [],
    String? brand,
  }) async {
    await _requireSession();
    try {
      await supabase.from('products').update({
        'name': name,
        'sku': sku,
        'unit': unit,
        'category_slug': categorySlug,
        'image_url': (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl,
        'pack_qty': packQty,
        'warranty_months': warrantyMonths,
        'attrs': attrs,
      }).eq('id', productId);

      await _setBrand(int.tryParse(productId) ?? productId, brand);
    } catch (e) {
      throw _dbFail(e, 'Не удалось изменить товар');
    }
  }

  /// Обновить цену/наличие. Если предложения ещё нет — создаём.
  ///
  /// [stockQty] и [leadTimeDays] (миграция 0029) пишем как есть, включая
  /// null: форма всегда присылает текущее состояние полей, и очистка поля
  /// должна доезжать до базы. Иначе поставщик не сможет убрать неверный
  /// остаток, а по нему покупатель планирует закупку.
  Future<void> saveOffer({
    String? offerId,
    required String productId,
    required String supplierId,
    required double price,
    required bool inStock,
    double? stockQty,
    int? leadTimeDays,
  }) async {
    final uid = await _requireSession();
    try {
      if (offerId == null) {
        await supabase.from('offers').insert({
          'product_id': productId,
          'supplier_id': supplierId,
          'owner_id': uid,
          'price': price,
          'in_stock': inStock,
          'stock_qty': stockQty,
          'lead_time_days': leadTimeDays,
        });
      } else {
        await supabase.from('offers').update({
          'price': price,
          'in_stock': inStock,
          'stock_qty': stockQty,
          'lead_time_days': leadTimeDays,
          'price_updated_at': DateTime.now().toIso8601String(),
        }).eq('id', offerId);
      }
    } catch (e) {
      throw _dbFail(e, 'Не удалось сохранить цену');
    }
  }

  Future<void> deleteProduct(String productId) async {
    await _requireSession();
    try {
      await supabase.from('products').delete().eq('id', productId);
    } catch (e) {
      throw _dbFail(e, 'Не удалось удалить товар');
    }
  }

  /// Массовый импорт прайса: товары + цены.
  ///
  /// Строки прайса склеиваются с карточками ОБЩЕГО каталога по
  /// нормализованному заводскому артикулу (см. [normSku]), а не по точному
  /// совпадению строки. Раньше «dd640200r» не находил карточку
  /// «DD640200R»: импорт пытался создать дубль, упирался в уникальный
  /// индекс `products_brand_sku_uniq` — и падал весь прайс целиком, а не
  /// одна строка. Теперь проблемная строка попадает в
  /// [ImportResult.failed], остальные загружаются.
  Future<ImportResult> importPrice({
    required List<PriceRow> rows,
    required String categorySlug,
    required String supplierId,
  }) async {
    final uid = await _requireSession();
    if (rows.isEmpty) return ImportResult.empty;

    // 0) Дубли внутри самого файла. Один товар в прайсе нередко встречается
    //    дважды; побеждает последняя строка — обычно это и есть свежая цена.
    //    Без этого две строки с одним артикулом гарантированно ломали
    //    вставку об уникальный индекс.
    final bySku = <String, PriceRow>{}; // нормализованный артикул -> строка
    final byName = <String, PriceRow>{}; // название + единица -> строка
    for (final r in rows) {
      final key = normSku(r.sku);
      if (key != null) {
        bySku[key] = r;
      } else {
        byName['${normName(r.name)}|${r.unit}'] = r;
      }
    }

    final failed = <String>[];
    String? firstError;
    // Строку не загрузили — запоминаем причину первой: «не вышло 40 строк»
    // без причины так же бесполезно, как прежнее падение всего файла.
    void fail(PriceRow r, Object e) {
      failed.add(r.name);
      firstError ??= _dbFail(e, 'Строка «${r.name}»').message;
    }

    try {
      // 1) Что из прайса уже есть в общем каталоге. Ищем во ВСЕХ карточках,
      //    а не только в своих: если этот керамогранит уже завёл другой
      //    поставщик, надо добавить цену к его карточке, а не плодить дубль.
      final existing = await _findProductsBySku(bySku.values.toList());
      // Строки без артикула — по названию, в пределах выбранной
      // категории и только при единственном кандидате.
      final existingByName =
          await _findProductsByName(byName.values.toList(), categorySlug);

      final matched = <Object, PriceRow>{}; // id карточки -> строка прайса
      final fresh = <PriceRow>[]; // карточек ещё нет — заводим
      bySku.forEach((key, row) {
        final id = existing[key];
        if (id != null) {
          matched[id] = row;
        } else {
          fresh.add(row);
        }
      });
      for (final row in byName.values) {
        final id = existingByName[normName(row.name)];
        if (id != null) {
          matched[id] = row;
        } else {
          fresh.add(row);
        }
      }

      // 2) Новые карточки — пачками. Пачка не прошла целиком: разбираем её
      //    по одной, чтобы потерять одну строку, а не весь прайс.
      var created = 0;
      for (final chunk in chunked(fresh, 100)) {
        try {
          created += await _insertNewProducts(
            rows: chunk,
            categorySlug: categorySlug,
            supplierId: supplierId,
            uid: uid,
          );
        } catch (chunkError) {
          if (!_isRowLevel(chunkError)) rethrow;
          for (final r in chunk) {
            try {
              created += await _insertNewProducts(
                rows: [r],
                categorySlug: categorySlug,
                supplierId: supplierId,
                uid: uid,
              );
            } catch (e) {
              if (!_isRowLevel(e)) rethrow;
              // Карточка с таким артикулом всё-таки есть — например, его
              // написали в регистре, которого не было среди наших
              // вариантов поиска. Это не повод терять строку: добавим
              // цену к найденной карточке.
              final id = await _findProductBySku(r.sku);
              if (id != null) {
                matched[id] = r;
              } else {
                fail(r, e);
              }
            }
          }
        }
      }

      // 3) Карточка уже в каталоге — трогаем только своё предложение.
      //    Чужую карточку не переписываем: название и фото там общие,
      //    правит их тот, кто её завёл (или администратор). Прежнюю цену
      //    запомнит и уведомит тех, у кого товар в избранном, сама база
      //    триггерами offers_track_price / offers_notify_price_drop.
      var priced = 0;
      if (matched.isNotEmpty) {
        final mine = await _myOfferIds(matched.keys.toList(), supplierId);
        final toInsert = <({String name, Map<String, dynamic> payload})>[];

        for (final e in matched.entries) {
          final offerId = mine[e.key];
          final sku = e.value.sku?.trim();
          if (offerId == null) {
            toInsert.add((
              name: e.value.name,
              payload: {
                'product_id': e.key,
                'supplier_id': supplierId,
                'owner_id': uid,
                'price': e.value.price,
                'in_stock': true,
                'stock_qty': e.value.stockQty,
                'lead_time_days': e.value.leadTimeDays,
                if (sku != null && sku.isNotEmpty) 'supplier_sku': sku,
              },
            ));
          } else {
            try {
              await supabase.from('offers').update({
                'price': e.value.price,
                'in_stock': true,
                // Колонки не было в файле — значит в прайсе про это ничего
                // не сказано, и уже сохранённые остаток и срок не затираем.
                if (e.value.stockQty != null) 'stock_qty': e.value.stockQty,
                if (e.value.leadTimeDays != null)
                  'lead_time_days': e.value.leadTimeDays,
                if (sku != null && sku.isNotEmpty) 'supplier_sku': sku,
              }).eq('id', offerId);
              priced++;
            } catch (err) {
              if (!_isRowLevel(err)) rethrow;
              fail(e.value, err);
            }
          }
        }

        for (final chunk in chunked(toInsert, 100)) {
          try {
            await supabase
                .from('offers')
                .insert(chunk.map((e) => e.payload).toList());
            priced += chunk.length;
          } catch (chunkError) {
            if (!_isRowLevel(chunkError)) rethrow;
            for (final one in chunk) {
              try {
                await supabase.from('offers').insert(one.payload);
                priced++;
              } catch (err) {
                if (!_isRowLevel(err)) rethrow;
                failed.add(one.name);
                firstError ??= _dbFail(err, 'Строка «${one.name}»').message;
              }
            }
          }
        }
      }

      return ImportResult(
        created: created,
        matched: priced,
        failed: failed,
        firstError: firstError,
      );
    } catch (e) {
      // Сюда доходят только общие отказы — нет связи, нет прав, нет
      // колонки. Построчные разобраны выше.
      if (e is Failure) rethrow; // у нашей ошибки текст уже понятный
      throw _dbFail(e, 'Не удалось загрузить прайс');
    }
  }

  /// Ищет карточки каталога по артикулам прайса: нормализованный
  /// артикул -> id карточки.
  ///
  /// Считает база (`match_products_by_sku`, миграция 0040): сравнение
  /// идёт по нормализованной колонке, поэтому покрывает все написания
  /// сразу, и заодно учитывает алиасы — артикулы карточек, которые
  /// администратор слил в эту. Без алиасов повторный импорт того же
  /// прайса заводил бы удалённый дубль заново.
  Future<Map<String, Object>> _findProductsBySku(List<PriceRow> rows) async {
    if (rows.isEmpty) return {};
    try {
      final res = await supabase.rpc('match_products_by_sku', params: {
        'p_skus': rows.map((r) => r.sku).whereType<String>().toList(),
      });
      final found = <String, Object>{};
      for (final row in (res as List).cast<Map<String, dynamic>>()) {
        final key = row['key_norm']?.toString();
        final id = row['match_id'];
        if (key != null && id != null) found[key] = id as Object;
      }
      return found;
    } catch (_) {
      // Миграции 0040 ещё нет — ищем сами, перебирая написания.
      return _findProductsBySkuFallback(rows);
    }
  }

  /// Карточки для строк БЕЗ артикула — по точному названию в пределах
  /// категории (`match_products_by_name`, миграция 0040).
  ///
  /// Это цемент, песок, штукатурка: заводского артикула у них не
  /// бывает, а карточка всё равно должна быть одна. База отдаёт
  /// совпадение только если подходящая карточка РОВНО ОДНА — два
  /// кандидата значит, что название неразличающее, и угадывать нельзя.
  /// Функции в базе нет — склейки по названию просто не будет, как и
  /// раньше: каждая такая строка заведёт свою карточку.
  Future<Map<String, Object>> _findProductsByName(
    List<PriceRow> rows,
    String categorySlug,
  ) async {
    if (rows.isEmpty) return {};
    try {
      final res = await supabase.rpc('match_products_by_name', params: {
        'p_names': rows.map((r) => r.name).toList(),
        'p_category': categorySlug,
      });
      final found = <String, Object>{};
      for (final row in (res as List).cast<Map<String, dynamic>>()) {
        final key = row['key_norm']?.toString();
        final id = row['match_id'];
        if (key != null && id != null) found[key] = id as Object;
      }
      return found;
    } catch (_) {
      return {};
    }
  }

  /// Запасной путь, пока миграции 0040 нет: спрашиваем сразу несколько
  /// написаний каждого артикула ([skuLookupVariants]), потому что
  /// PostgREST сравнивает `in` регистрозависимо.
  Future<Map<String, Object>> _findProductsBySkuFallback(
      List<PriceRow> rows) async {
    final variants = <String>{};
    for (final r in rows) {
      variants.addAll(skuLookupVariants(r.sku));
    }
    final found = <String, Object>{};
    if (variants.isEmpty) return found;
    for (final chunk in chunked(variants.toList(), 150)) {
      final res =
          await supabase.from('products').select('id,sku').inFilter('sku', chunk);
      for (final row in res) {
        final key = normSku(row['sku']?.toString());
        final id = row['id'];
        // Если дубли карточек уже есть, берём первую — склеивать их
        // самостоятельно импорт не вправе, это работа администратора.
        if (key != null && id != null) found.putIfAbsent(key, () => id as Object);
      }
    }
    return found;
  }

  /// Одна карточка по артикулу — запасной путь, когда вставка упёрлась
  /// в уникальный индекс.
  Future<Object?> _findProductBySku(String? sku) async {
    final key = normSku(sku);
    if (key == null) return null;
    try {
      final res = await supabase
          .from('products')
          .select('id,sku')
          .inFilter('sku', skuLookupVariants(sku));
      for (final row in res) {
        if (normSku(row['sku']?.toString()) == key) return row['id'] as Object?;
      }
    } catch (_) {
      // Не нашли — строка уйдёт в «не загрузилось» с причиной от вставки.
    }
    return null;
  }

  /// Мои предложения на эти карточки: id карточки -> id предложения.
  /// Один запрос вместо запроса на каждую строку прайса.
  Future<Map<Object, Object>> _myOfferIds(
    List<Object> productIds,
    String supplierId,
  ) async {
    final map = <Object, Object>{};
    for (final chunk in chunked(productIds, 150)) {
      final res = await supabase
          .from('offers')
          .select('id,product_id')
          .eq('supplier_id', supplierId)
          .inFilter('product_id', chunk);
      for (final row in res) {
        final pid = row['product_id'];
        final oid = row['id'];
        if (pid != null && oid != null) map[pid as Object] = oid as Object;
      }
    }
    return map;
  }

  /// Заводит новые карточки и сразу свои цены к ним.
  /// Возвращает число загруженных позиций.
  Future<int> _insertNewProducts({
    required List<PriceRow> rows,
    required String categorySlug,
    required String supplierId,
    required String uid,
  }) async {
    if (rows.isEmpty) return 0;
    // Фото сразу в products.image_url — так его читает веб-версия.
    final inserted = await supabase
        .from('products')
        .insert(rows
            .map((r) => {
                  'name': r.name,
                  'sku': r.sku,
                  'unit': r.unit,
                  'category_slug': categorySlug,
                  'image_url': (r.imageUrl == null || r.imageUrl!.isEmpty)
                      ? null
                      : r.imageUrl,
                  'owner_id': uid,
                })
            .toList())
        .select('id,sku');

    if (inserted.length != rows.length) {
      throw Failure('база завела ${inserted.length} карточек '
          'из ${rows.length} — цены не расставить');
    }

    // Строки с артикулом сопоставляем по нему, остальные — по порядку
    // вставки (он сохраняется, длины уже сверены).
    final byNorm = <String, Object>{};
    for (final row in inserted) {
      final key = normSku(row['sku']?.toString());
      final id = row['id'];
      if (key != null && id != null) byNorm[key] = id as Object;
    }

    final offers = <Map<String, dynamic>>[];
    for (var i = 0; i < rows.length; i++) {
      final key = normSku(rows[i].sku);
      final id = key != null ? byNorm[key] : inserted[i]['id'];
      if (id == null) throw const Failure('не удалось связать цену с товаром');
      offers.add({
        'product_id': id,
        'supplier_id': supplierId,
        'owner_id': uid,
        'price': rows[i].price,
        'in_stock': true,
        'stock_qty': rows[i].stockQty,
        'lead_time_days': rows[i].leadTimeDays,
      });
    }

    try {
      await supabase.from('offers').insert(offers);
    } catch (_) {
      // Карточка без цены в каталоге бесполезна и мешает повторному
      // импорту (в следующий раз она найдётся как существующая, и
      // поставщик не поймёт, почему цены нет). Транзакций из клиента нет,
      // поэтому откатываем вставку руками.
      try {
        await supabase.from('products').delete().inFilter(
            'id', inserted.map((r) => r['id'] as Object).toList());
      } catch (_) {
        // Откат не прошёл — пусть лучше останется карточка без цены,
        // чем импорт свалится на попытке убрать её.
      }
      rethrow;
    }
    return rows.length;
  }

  /// Статистика просмотров/обращений по моим товарам.
  ///
  /// Сначала пробуем функцию supplier_stats (миграция 0010). Если её в базе
  /// ещё нет — считаем сами по таблице events, чтобы кабинет не пустовал.
  Future<Map<String, ProductStat>> stats(String supplierId) async {
    try {
      final rows = await supabase
          .rpc('supplier_stats', params: {'p_supplier': int.tryParse(supplierId) ?? supplierId});
      final map = <String, ProductStat>{};
      for (final r in (rows as List)) {
        final m = r as Map<String, dynamic>;
        map[m['product_id'].toString()] = ProductStat(
          (m['views'] as num?)?.toInt() ?? 0,
          (m['contacts'] as num?)?.toInt() ?? 0,
        );
      }
      return map;
    } catch (_) {
      return _statsFromEvents(supplierId);
    }
  }

  Future<Map<String, ProductStat>> _statsFromEvents(String supplierId) async {
    try {
      final rows = await supabase
          .from('events')
          .select('type,product_id')
          .eq('supplier_id', supplierId)
          .limit(5000);
      final map = <String, ProductStat>{};
      for (final r in rows) {
        final pid = r['product_id']?.toString();
        if (pid == null) continue;
        final type = (r['type'] ?? '').toString();
        final prev = map[pid] ?? const ProductStat(0, 0);
        final isContact =
            type == 'contact' || type == 'call' || type == 'whatsapp';
        map[pid] = ProductStat(
          prev.views + (isContact ? 0 : 1),
          prev.contacts + (isContact ? 1 : 0),
        );
      }
      return map;
    } catch (_) {
      // статистика не критична — кабинет работает и без неё
      return {};
    }
  }

  /// Заявка на статус поставщика: профиль переходит в supplier/pending.
  /// Одобряет администратор в панели admin.html.
  Future<void> becomeSupplier({
    required String company,
    String? city,
    String? phone,
  }) async {
    await _requireSession();
    if (company.trim().isEmpty) {
      throw const Failure('Укажите название компании');
    }
    try {
      await supabase.rpc('become_supplier', params: {
        'p_company': company.trim(),
        'p_city': city?.trim(),
        'p_phone': phone?.trim(),
      });
    } catch (e) {
      if (e.toString().contains('become_supplier')) {
        throw const Failure(
            'Приём заявок ещё не настроен на сервере — примените миграцию 0010');
      }
      throw mapError(e, fallback: 'Не удалось оформить заявку');
    }
  }
}
