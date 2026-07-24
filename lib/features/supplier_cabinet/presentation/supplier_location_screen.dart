import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/data_refresh.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../suppliers_map/data/geocoding_service.dart';
import 'supplier_cabinet_providers.dart';

/// Экран «Место на карте» для кабинета поставщика.
///
/// Поставщик пишет адрес — мы находим его на карте (геокодер), а точную
/// точку он ставит, двигая карту под неподвижной булавкой в центре.
/// Сохраняем адрес и координаты центра.
class SupplierLocationScreen extends ConsumerStatefulWidget {
  const SupplierLocationScreen({super.key});

  @override
  ConsumerState<SupplierLocationScreen> createState() =>
      _SupplierLocationScreenState();
}

class _SupplierLocationScreenState
    extends ConsumerState<SupplierLocationScreen> {
  final _map = MapController();
  final _address = TextEditingController();

  // Центр карты = будущая точка компании. Стартовое значение — Астана.
  LatLng _center = const LatLng(51.1280, 71.4304);
  bool _searching = false;
  bool _saving = false;
  bool _ready = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  /// Подставляем то, что уже есть у компании (адрес и точку).
  void _prefill() {
    if (_ready) return;
    _ready = true;
    final comp = ref.read(myCompanyProvider).valueOrNull;
    if (comp == null) return;
    if ((comp.address ?? '').isNotEmpty) _address.text = comp.address!;
    if (comp.hasLocation) {
      _center = LatLng(comp.lat!, comp.lng!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _map.move(_center, 16);
      });
    }
  }

  Future<void> _find() async {
    final q = _address.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    final messenger = ScaffoldMessenger.of(context);

    final res = await ref.read(geocodingServiceProvider).search(q);

    if (!mounted) return;
    setState(() => _searching = false);
    if (res == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Адрес не найден — поставьте булавку на карте вручную')));
      return;
    }
    _center = LatLng(res.lat, res.lng);
    _map.move(_center, 16);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ref.read(supplierCabinetRepositoryProvider).saveLocation(
            address: _address.text,
            lat: _center.latitude,
            lng: _center.longitude,
          );
      // Чтобы новая точка сразу была видна на карте и в кабинете
      refreshAppData(ref);
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Место сохранено')));
      nav.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final t = e.toString();
      messenger.showSnackBar(SnackBar(
          content: Text(t.startsWith('Failure: ') ? t.substring(9) : 'Ошибка')));
    }
  }

  @override
  Widget build(BuildContext context) {
    _prefill();
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Место на карте')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _address,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _find(),
                    decoration: const InputDecoration(
                      hintText: 'Город, улица, дом',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: _searching ? null : _find,
                    child: _searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Найти'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 12,
                    minZoom: 4,
                    maxZoom: 18,
                    // Центр карты и есть выбираемая точка — запоминаем при
                    // каждом сдвиге
                    onPositionChanged: (pos, _) => _center = pos.center,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'kz.komplekt.app',
                    ),
                  ],
                ),
                // Неподвижная булавка в центре: куда указывает — там и точка
                IgnorePointer(
                  child: Padding(
                    // приподнимаем, чтобы остриё показывало на центр
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Icon(Icons.location_on, size: 48, color: c.orange),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.card.withOpacity(0.95),
                      border: Border.all(color: c.line),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Двигайте карту так, чтобы булавка указывала на вход. '
                      'Она отмечает место компании.',
                      style: TextStyle(fontSize: 12, color: c.gray),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Сохранить место'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
