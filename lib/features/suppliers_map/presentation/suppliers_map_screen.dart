import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/supplier.dart';
import 'suppliers_providers.dart';

/// Экран 6 — Поставщики на карте (flutter_map + OpenStreetMap, без ключей).
class SuppliersMapScreen extends ConsumerWidget {
  const SuppliersMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final location = ref.watch(userLocationProvider);
    final suppliers = ref.watch(nearbySuppliersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Поставщики рядом')),
      body: location.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (_, __) => const Center(child: Text('Не удалось определить местоположение')),
        data: (loc) {
          final center = LatLng(loc.lat, loc.lng);
          final list = suppliers.valueOrNull ?? const <Supplier>[];

          return Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 12,
                  minZoom: 4,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'kz.komplekt.app',
                  ),
                  MarkerLayer(
                    markers: [
                      // Метка пользователя
                      Marker(
                        point: center,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                      // Метки поставщиков
                      for (final s in list)
                        if (s.hasLocation)
                          Marker(
                            point: LatLng(s.lat!, s.lng!),
                            width: 44,
                            height: 44,
                            child: GestureDetector(
                              onTap: () => _showSupplier(context, s),
                              child: Icon(Icons.location_on,
                                  color: c.orange, size: 40),
                            ),
                          ),
                    ],
                  ),
                ],
              ),

              if (loc.isDefault)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: _InfoBanner(
                    'Геолокация недоступна — показан центр города. '
                    'Разрешите доступ к локации для точного поиска.',
                  ),
                ),

              // Счётчик найденных
              Positioned(
                left: 16,
                bottom: 16,
                child: suppliers.isLoading
                    ? _Pill(child: const _MiniLoader())
                    : _Pill(
                        child: Text('Найдено: ${list.length}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13))),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSupplier(BuildContext context, Supplier s) {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.star_rounded, size: 16, color: c.orange),
                const SizedBox(width: 4),
                Text(s.rating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (s.distanceLabel != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.near_me_outlined, size: 15, color: c.gray),
                  const SizedBox(width: 4),
                  Text(s.distanceLabel!,
                      style: TextStyle(color: c.gray, fontSize: 13)),
                ],
              ],
            ),
            if (s.address != null) ...[
              const SizedBox(height: 8),
              Text(s.address!, style: TextStyle(color: c.gray, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(Routes.supplier(s.id));
                },
                child: const Text('Открыть витрину'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: c.orange),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, color: c.gray))),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
