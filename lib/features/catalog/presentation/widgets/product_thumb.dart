import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/category_icons.dart';
import '../../domain/product.dart';

/// Превью товара: фото из базы либо заглушка по категории (как в прототипе).
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    required this.product,
    this.size = 68,
    this.radius = 11,
  });

  final Product product;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = product.primaryImageUrl;
    final bg = product.placeholderColor ?? c.field;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: c.field),
                errorWidget: (_, __, ___) => _placeholder(bg, c),
              )
            : _placeholder(bg, c),
      ),
    );
  }

  Widget _placeholder(Color bg, AppColors c) {
    // Контрастная иконка категории поверх цветной подложки
    final onBg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white70
        : c.ink.withOpacity(0.55);
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Icon(CategoryIcons.of(product.categorySlug),
          size: size * 0.42, color: onBg),
    );
  }
}
