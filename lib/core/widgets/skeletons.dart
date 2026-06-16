import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

/// Скелетон списка товаров (shimmer) для состояния загрузки.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 11),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: c.field,
        highlightColor: c.card,
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
    );
  }
}
