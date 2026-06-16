import '../../features/auth/domain/app_user.dart';
import '../../features/catalog/domain/category.dart';
import '../../features/catalog/domain/offer.dart';
import '../../features/catalog/domain/product.dart';
import '../../features/collections/domain/collection.dart';
import '../../features/suppliers_map/domain/supplier.dart';

/// Встроенные данные для демо-режима (без Supabase).
/// Зеркалят сид-данные из supabase/migrations/0002_seed.sql.
class DemoData {
  DemoData._();

  static const user = AppUser(
    id: 'demo-user',
    fullName: 'Гость (демо)',
    city: 'Астана',
    role: 'buyer',
    status: 'approved',
  );

  static const categories = <Category>[
    Category(slug: 'tile', name: 'Керамогранит', icon: 'tile', sort: 1),
    Category(slug: 'laminate', name: 'Ламинат', icon: 'laminate', sort: 2),
    Category(slug: 'plumbing', name: 'Сантехника', icon: 'plumbing', sort: 3),
    Category(slug: 'light', name: 'Освещение', icon: 'light', sort: 4),
    Category(slug: 'electric', name: 'Электрика', icon: 'electric', sort: 5),
    Category(slug: 'doors', name: 'Двери', icon: 'doors', sort: 6),
    Category(slug: 'paint', name: 'Краска', icon: 'paint', sort: 7),
    Category(slug: 'furniture', name: 'Мебель', icon: 'furniture', sort: 8),
    Category(slug: 'decor', name: 'Декор', icon: 'decor', sort: 9),
    Category(slug: 'wallpaper', name: 'Обои', icon: 'wallpaper', sort: 10),
  ];

  static const suppliers = <Supplier>[
    Supplier(
        id: 's1',
        name: 'Keramo City',
        city: 'Астана',
        address: 'пр. Кабанбай батыра, 53',
        phone: '+7 701 111 11 11',
        whatsapp: '77011111111',
        website: 'https://keramocity.kz',
        rating: 4.7,
        lat: 51.0905,
        lng: 71.4180),
    Supplier(
        id: 's2',
        name: 'СтройДом KZ',
        city: 'Астана',
        address: 'ул. Сарыарка, 12',
        phone: '+7 701 222 22 22',
        whatsapp: '77012222222',
        website: 'https://stroydom.kz',
        rating: 4.5,
        lat: 51.1605,
        lng: 71.4704),
    Supplier(
        id: 's3',
        name: 'ЕвроКерамика',
        city: 'Астана',
        address: 'пр. Туран, 37',
        phone: '+7 701 333 33 33',
        whatsapp: '77013333333',
        rating: 4.6,
        lat: 51.1280,
        lng: 71.4304),
    Supplier(
        id: 's4',
        name: 'Пол и Точка',
        city: 'Астана',
        address: 'ул. Бейбитшилик, 25',
        phone: '+7 701 444 44 44',
        whatsapp: '77014444444',
        rating: 4.4,
        lat: 51.1700,
        lng: 71.4200),
    Supplier(
        id: 's5',
        name: 'Svet Pro',
        city: 'Астана',
        address: 'пр. Республики, 5',
        phone: '+7 701 555 55 55',
        whatsapp: '77015555555',
        website: 'https://svetpro.kz',
        rating: 4.8,
        lat: 51.1470,
        lng: 71.4060),
  ];

  static final Map<String, Supplier> _byId = {
    for (final s in suppliers) s.id: s,
  };

  static Offer _offer(String supplierId, double price, bool stock) {
    final s = _byId[supplierId]!;
    return Offer(
      id: 'of_${supplierId}_${price.toInt()}',
      price: price,
      inStock: stock,
      supplierId: s.id,
      supplierName: s.name,
      city: s.city,
      phone: s.phone,
      whatsapp: s.whatsapp,
      website: s.website,
      priceUpdatedAt: DateTime.now(),
    );
  }

  static final List<Product> products = [
    Product(
      id: 'p1',
      name: 'Керамогранит Cersanit Concretehouse серый 29,7×59,8',
      categorySlug: 'tile',
      brand: 'Cersanit',
      sku: 'C-CH4L092D',
      unit: 'м²',
      color: '#cdc8bd',
      offers: [_offer('s1', 4290, true), _offer('s2', 4450, true), _offer('s3', 5100, false)],
    ),
    Product(
      id: 'p2',
      name: 'Керамогранит Kerama Marazzi Про Фьюче беж 60×60',
      categorySlug: 'tile',
      brand: 'Kerama Marazzi',
      sku: 'DD640200R',
      unit: 'м²',
      color: '#ddd3c3',
      offers: [_offer('s3', 7850, true), _offer('s1', 8200, true)],
    ),
    Product(
      id: 'p3',
      name: 'Ламинат Kronospan Castello Дуб горный 8 мм / 32 кл.',
      categorySlug: 'laminate',
      brand: 'Kronospan',
      sku: 'K063 SU',
      unit: 'м²',
      color: '#b9874c',
      offers: [_offer('s4', 3150, true), _offer('s2', 3290, true)],
    ),
    Product(
      id: 'p4',
      name: 'Краска Tikkurila Euro Power 7 база A, 9 л',
      categorySlug: 'paint',
      brand: 'Tikkurila',
      sku: '700001122',
      unit: 'шт',
      color: '#eae4d8',
      offers: [_offer('s2', 28900, true)],
    ),
    Product(
      id: 'p5',
      name: 'Трековый светильник Maytoni Focus LED 12W 4000K',
      categorySlug: 'light',
      brand: 'Maytoni',
      sku: 'TR032-2-12W4K-B',
      unit: 'шт',
      color: '#26292d',
      offers: [_offer('s5', 14200, true), _offer('s1', 16300, true)],
    ),
    Product(
      id: 'p6',
      name: 'Смеситель Grohe BauEdge для раковины, хром',
      categorySlug: 'plumbing',
      brand: 'Grohe',
      sku: '23758000',
      unit: 'шт',
      color: '#dde6ea',
      offers: [_offer('s2', 21500, true)],
    ),
  ];

  static Product? productById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ── Изменяемое состояние демо: избранное и подборки ──
  static final Set<String> favorites = {'p2'};

  static final List<Collection> collections = [
    Collection(
      id: 'c1',
      name: 'Кафе · Астана',
      items: [
        CollectionItem(id: 'ci1', productId: 'p1', qty: 86, product: productById('p1')),
        CollectionItem(id: 'ci2', productId: 'p5', qty: 14, product: productById('p5')),
      ],
    ),
  ];
}
