import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../catalog/domain/product.dart';
import '../../suppliers_map/domain/supplier.dart';

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

/// Импортируемая строка прайса (после сопоставления колонок).
class PriceRow {
  PriceRow({
    required this.name,
    required this.price,
    this.sku,
    this.unit = 'шт',
    this.imageUrl,
  });
  final String name;
  final double price;
  final String? sku;
  final String unit;
  final String? imageUrl;
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
      });
    } catch (e) {
      throw _dbFail(e, 'Не удалось сохранить товар');
    }
  }

  /// Поднять своё предложение в топ списков на [days] дней.
  ///
  /// Доступно только на тарифе Pro — проверку делает база. На порядок
  /// в шкале цен внутри карточки товара это не влияет: там всегда
  /// первым идёт тот, у кого дешевле.
  Future<DateTime?> promoteOffer(String offerId, {int days = 7}) async {
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

  /// Изменить карточку товара: название, артикул, единицу, категорию, фото.
  /// Цена живёт отдельно, в предложении — её меняет [saveOffer].
  Future<void> updateProduct({
    required String productId,
    required String name,
    required String categorySlug,
    required String unit,
    String? sku,
    String? imageUrl,
  }) async {
    await _requireSession();
    try {
      await supabase.from('products').update({
        'name': name,
        'sku': sku,
        'unit': unit,
        'category_slug': categorySlug,
        'image_url': (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl,
      }).eq('id', productId);
    } catch (e) {
      throw _dbFail(e, 'Не удалось изменить товар');
    }
  }

  /// Обновить цену/наличие. Если предложения ещё нет — создаём.
  Future<void> saveOffer({
    String? offerId,
    required String productId,
    required String supplierId,
    required double price,
    required bool inStock,
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
        });
      } else {
        await supabase.from('offers').update({
          'price': price,
          'in_stock': inStock,
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

  /// Массовый импорт прайса: товары + цены одной пачкой.
  /// Возвращает количество загруженных позиций.
  Future<int> importPrice({
    required List<PriceRow> rows,
    required String categorySlug,
    required String supplierId,
  }) async {
    final uid = await _requireSession();
    if (rows.isEmpty) return 0;
    try {
      // 0) Что из прайса уже есть в ОБЩЕМ каталоге.
      //
      //    Ищем по артикулу производителя во всех карточках, а не только
      //    в своих: если этот керамогранит уже завёл другой поставщик,
      //    мы должны добавить цену к его карточке, а не плодить дубль.
      final skus = rows
          .map((r) => r.sku?.trim())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      final existing = <String, dynamic>{}; // артикул -> id карточки
      if (skus.isNotEmpty) {
        final found = await supabase
            .from('products')
            .select('id,sku')
            .inFilter('sku', skus);
        for (final row in found) {
          final sku = row['sku']?.toString();
          if (sku != null && sku.isNotEmpty) existing[sku] = row['id'];
        }
      }

      final newRows = <PriceRow>[];
      final updates = <MapEntry<dynamic, PriceRow>>[]; // id товара -> строка
      for (final r in rows) {
        final sku = r.sku?.trim();
        final id = (sku != null && sku.isNotEmpty) ? existing[sku] : null;
        if (id != null) {
          updates.add(MapEntry(id, r));
        } else {
          newRows.add(r);
        }
      }

      // 1) новые товары пачкой — фото сразу в products.image_url, как в вебе
      if (newRows.isNotEmpty) {
        final productsPayload = newRows
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
            .toList();
        final inserted = await supabase
            .from('products')
            .insert(productsPayload)
            .select('id');

        // 2) к каждому — цена (порядок вставки сохраняется)
        final offersPayload = <Map<String, dynamic>>[];
        for (var i = 0; i < inserted.length; i++) {
          offersPayload.add({
            'product_id': inserted[i]['id'],
            'supplier_id': supplierId,
            'owner_id': uid,
            'price': newRows[i].price,
            'in_stock': true,
          });
        }
        await supabase.from('offers').insert(offersPayload);
      }

      // 3) карточка уже в каталоге — трогаем только своё предложение.
      //    Чужую карточку не переписываем: название и фото там общие,
      //    и правит их тот, кто её завёл (или администратор).
      //    Триггер в базе сам запомнит прежнюю цену и уведомит тех,
      //    у кого товар в избранном.
      for (final e in updates) {
        final offer = await supabase
            .from('offers')
            .select('id')
            .eq('product_id', e.key)
            .eq('supplier_id', supplierId)
            .maybeSingle();

        final sku = e.value.sku?.trim();
        if (offer == null) {
          await supabase.from('offers').insert({
            'product_id': e.key,
            'supplier_id': supplierId,
            'owner_id': uid,
            'price': e.value.price,
            'in_stock': true,
            if (sku != null && sku.isNotEmpty) 'supplier_sku': sku,
          });
        } else {
          await supabase.from('offers').update({
            'price': e.value.price,
            'in_stock': true,
            if (sku != null && sku.isNotEmpty) 'supplier_sku': sku,
          }).eq('id', offer['id']);
        }
      }

      return newRows.length + updates.length;
    } catch (e) {
      throw _dbFail(e, 'Не удалось загрузить прайс');
    }
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
