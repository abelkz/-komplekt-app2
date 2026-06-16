import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/price_drop.dart';

/// История уведомлений о снижении цены.
final notificationsProvider = FutureProvider<List<PriceDrop>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(notificationsRepositoryProvider).list();
});

/// Количество непрочитанных уведомлений (бейдж на колоколе).
final unreadCountProvider = FutureProvider<int>((ref) {
  ref.watch(authStateProvider);
  return ref.read(notificationsRepositoryProvider).unreadCount();
});
