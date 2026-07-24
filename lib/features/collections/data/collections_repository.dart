import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../catalog/data/catalog_repository.dart';
import '../domain/collection.dart';

/// Подборки/проекты пользователя и позиции в них.
/// В живой базе таблицы называются projects и project_items.
class CollectionsRepository {
  const CollectionsRepository();

  String? get _uid => supabase.auth.currentUser?.id;

  static const _select = 'id,name,created_at,'
      'project_items(id,product_id,qty,'
      'products(${CatalogRepository.productSelect}))';

  /// Все подборки пользователя.
  Future<List<Collection>> list() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await supabase
          .from('projects')
          .select(_select)
          .eq('user_id', uid)
          .order('created_at');
      return rows.map<Collection>((m) => Collection.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить подборки');
    }
  }

  /// Найти первую подборку или создать «Мой проект» (для быстрого добавления).
  Future<Collection> ensureDefault() async {
    final all = await list();
    if (all.isNotEmpty) return all.first;
    final id = await create('Мой проект');
    return Collection(id: id, name: 'Мой проект');
  }

  /// Сколько подборок можно завести без тарифа.
  static const freeLimit = 3;

  /// Действует ли оплаченный «КОМПЛЕКТ Про».
  /// Колонки может не быть (миграция 0017) — тогда считаем, что тарифа нет.
  Future<bool> _isPro(String uid) async {
    try {
      final p = await supabase
          .from('profiles')
          .select('plan,plan_until')
          .eq('id', uid)
          .maybeSingle();
      if (p == null || p['plan'] != 'pro') return false;
      final until = DateTime.tryParse(p['plan_until'] as String? ?? '');
      return until == null || until.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Future<String> create(String name) async {
    final uid = _uid;
    if (uid == null) throw const Failure('Войдите, чтобы создать подборку');

    final mine = await supabase.from('projects').select('id').eq('user_id', uid);
    if (mine.length >= freeLimit && !await _isPro(uid)) {
      throw const Failure(
          'Без тарифа можно вести $freeLimit подборки. '
          'В КОМПЛЕКТ Про их сколько угодно');
    }

    try {
      final row = await supabase
          .from('projects')
          .insert({'user_id': uid, 'name': name})
          .select('id')
          .single();
      return row['id'].toString();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось создать подборку');
    }
  }

  Future<void> rename(String collectionId, String name) async {
    try {
      await supabase
          .from('projects')
          .update({'name': name}).eq('id', collectionId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось переименовать');
    }
  }

  Future<void> deleteCollection(String collectionId) async {
    try {
      await supabase.from('projects').delete().eq('id', collectionId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось удалить подборку');
    }
  }

  /// Добавить товар. Upsert не используем: он требует уникального индекса
  /// (project_id, product_id), которого в живой базе может не быть —
  /// вместо этого сами проверяем, есть ли уже такая позиция.
  Future<void> addItem({
    required String collectionId,
    required String productId,
    double qty = 1,
  }) async {
    try {
      final existing = await supabase
          .from('project_items')
          .select('id,qty')
          .eq('project_id', collectionId)
          .eq('product_id', productId)
          .maybeSingle();
      if (existing == null) {
        await supabase.from('project_items').insert({
          'project_id': collectionId,
          'product_id': productId,
          'qty': qty,
        });
      } else {
        await supabase
            .from('project_items')
            .update({'qty': ((existing['qty'] as num?)?.toDouble() ?? 0) + qty})
            .eq('id', existing['id']);
      }
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось добавить в подборку');
    }
  }

  Future<void> setQty({
    required String collectionId,
    required String productId,
    required double qty,
  }) async {
    try {
      if (qty <= 0) {
        await removeItem(collectionId: collectionId, productId: productId);
        return;
      }
      await supabase
          .from('project_items')
          .update({'qty': qty})
          .eq('project_id', collectionId)
          .eq('product_id', productId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось изменить количество');
    }
  }

  Future<void> removeItem({
    required String collectionId,
    required String productId,
  }) async {
    try {
      await supabase
          .from('project_items')
          .delete()
          .eq('project_id', collectionId)
          .eq('product_id', productId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось убрать позицию');
    }
  }
}
