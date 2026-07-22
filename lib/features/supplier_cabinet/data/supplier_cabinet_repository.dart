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

  /// Мои товары (созданные мной) с моей ценой и фото.
  Future<List<Product>> myProducts() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await supabase
          .from('products')
          .select('id,name,sku,unit,color,image_url,category_slug,'
              'brands(name),'
              'product_images(url,sort),'
              'offers(id,price,in_stock,price_updated_at,supplier_id)')
          .eq('owner_id', uid)
          .order('id', ascending: false);
      return rows.map<Product>((m) => Product.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить товары');
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
      // 1) товары пачкой — фото сразу в products.image_url, как в вебе
      final productsPayload = rows
          .map((r) => {
                'name': r.name,
                'sku': r.sku,
                'unit': r.unit,
                'category_slug': categorySlug,
                'image_url':
                    (r.imageUrl == null || r.imageUrl!.isEmpty) ? null : r.imageUrl,
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
          'price': rows[i].price,
          'in_stock': true,
        });
      }
      await supabase.from('offers').insert(offersPayload);
      return inserted.length;
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
