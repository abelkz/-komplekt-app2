import 'product.dart';

/// Товар, у которого за период упала минимальная цена.
///
/// Отличается от `Product.savingPercent`, и различие принципиальное:
/// savingPercent — разброс между самым дешёвым и самым дорогим предложением
/// прямо сейчас («где переплачивают»), а здесь — падение во времени
/// («где подешевело»). Первое не меняется, пока поставщики стоят на своих
/// ценах; второе и есть повод вернуться в приложение.
class PriceDrop {
  const PriceDrop({
    required this.product,
    required this.oldPrice,
    required this.newPrice,
    required this.percent,
  });

  final Product product;

  /// Минимальная цена на начало периода.
  final double oldPrice;

  /// Минимальная цена сейчас.
  final double newPrice;

  /// На сколько процентов упала, целое положительное число.
  final int percent;

  double get amount => oldPrice - newPrice;
}
