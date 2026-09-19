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

final boostOrdersProvider = FutureProvider<List<SubRequest>>(
    (ref) => ref.read(adminRepositoryProvider).boostOrders());

final contentReportsProvider = FutureProvider<List<ContentReport>>(
    (ref) => ref.read(adminRepositoryProvider).reports());

// ─────────────────────────── Статистика ───────────────────────────

/// За сколько дней смотрим сводку. Общий для всей вкладки: переключил
/// период — пересчитались сразу все панели, а не каждая по отдельности.
class StatsPeriodNotifier extends Notifier<int> {
  @override
  int build() => 30;
  void set(int days) => state = days;
}

final statsPeriodProvider =
    NotifierProvider<StatsPeriodNotifier, int>(StatsPeriodNotifier.new);

final adminOverviewProvider = FutureProvider<AdminOverview>((ref) => ref
    .read(adminRepositoryProvider)
    .overview(days: ref.watch(statsPeriodProvider)));

final adminTopSearchesProvider = FutureProvider<List<CountedRow>>((ref) => ref
    .read(adminRepositoryProvider)
    .topSearches(days: ref.watch(statsPeriodProvider)));

final adminTopCategoriesProvider = FutureProvider<List<CountedRow>>((ref) => ref
    .read(adminRepositoryProvider)
    .topCategories(days: ref.watch(statsPeriodProvider)));

final adminSupplierStatsProvider = FutureProvider<List<SupplierRow>>((ref) => ref
    .read(adminRepositoryProvider)
    .supplierStats(days: ref.watch(statsPeriodProvider)));

/// Сколько дел ждёт решения — число на вкладке профиля.
final adminPendingCountProvider = Provider<int>((ref) {
  final suppliers = ref.watch(supplierApplicationsProvider).valueOrNull ?? [];
  final subs = ref.watch(subscriptionRequestsProvider).valueOrNull ?? [];
  final boosts = ref.watch(boostOrdersProvider).valueOrNull ?? [];
  final reports = ref.watch(contentReportsProvider).valueOrNull ?? [];
  return suppliers.where((s) => s.isPending).length +
      subs.where((s) => s.isNew).length +
      boosts.where((s) => s.isNew).length +
      reports.where((r) => r.isNew).length;
});
