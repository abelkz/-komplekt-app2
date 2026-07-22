import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../domain/photo_match.dart';

/// Состояние экрана «Поиск по фото»: выбранное фото и результат разбора.
class VisualSearchState {
  const VisualSearchState({this.photo, this.result});

  /// Байты выбранного снимка — показываем его над результатом
  final Uint8List? photo;
  final PhotoMatch? result;
}

class VisualSearchNotifier extends AsyncNotifier<VisualSearchState> {
  @override
  Future<VisualSearchState> build() async => const VisualSearchState();

  /// Отправить снимок на распознавание.
  Future<void> analyze(Uint8List bytes, {String mediaType = 'image/jpeg'}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final match = await ref
          .read(visualSearchRepositoryProvider)
          .analyze(bytes, mediaType: mediaType);
      return VisualSearchState(photo: bytes, result: match);
    });
  }

  void reset() => state = const AsyncData(VisualSearchState());
}

final visualSearchProvider =
    AsyncNotifierProvider<VisualSearchNotifier, VisualSearchState>(
        VisualSearchNotifier.new);
