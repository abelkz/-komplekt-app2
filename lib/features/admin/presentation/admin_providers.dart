import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/admin_repository.dart';

final adminRepositoryProvider = Provider((ref) => const AdminRepository());

/// Панель доступна только администратору. Это удобство интерфейса —
/// настоящая защита в политиках базы: остальным она ничего не отдаст.
final isAdminProvider = Provider<bool>((ref) =>
    ref.watch(myProfileProvider).valueOrNull?.role == 'admin');

final supplierApplicationsProvider = FutureProvider<List<AppUser>>(
    (ref) => ref.read(adminRepositoryProvider).suppliers());

final subscriptionRequestsProvider = FutureProvider<List<SubRequest>>(
    (ref) => ref.read(adminRepositoryProvider).subscriptions());

/// Сколько дел ждёт решения — число на вкладке профиля.
final adminPendingCountProvider = Provider<int>((ref) {
  final suppliers = ref.watch(supplierApplicationsProvider).valueOrNull ?? [];
  final subs = ref.watch(subscriptionRequestsProvider).valueOrNull ?? [];
  return suppliers.where((s) => s.isPending).length +
      subs.where((s) => s.isNew).length;
});
