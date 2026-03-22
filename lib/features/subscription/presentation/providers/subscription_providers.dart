import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/subscription/data/firebase_subscription_repository.dart';
import 'package:buildtrack_app/features/subscription/data/firebase_usage_quota_repository.dart';
import 'package:buildtrack_app/features/subscription/data/revenuecat_purchase_coordinator.dart';
import 'package:buildtrack_app/features/subscription/domain/entitlement_guard_service.dart';
import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final purchaseCoordinatorProvider = Provider<PurchaseCoordinator>((ref) {
  return RevenueCatPurchaseCoordinator();
});

final revenueCatBootstrapProvider = FutureProvider<void>((ref) async {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return;
  }
  await ref.read(purchaseCoordinatorProvider).configure(appUserId: workspaceId);
});

final revenueCatCustomerInfoProvider = FutureProvider<CustomerSubscriptionInfo>(
  (ref) async {
    await ref.watch(revenueCatBootstrapProvider.future);
    return ref.read(purchaseCoordinatorProvider).getCustomerInfo();
  },
);

final revenueCatCustomerInfoStreamProvider =
    StreamProvider<CustomerSubscriptionInfo>((ref) async* {
      await ref.watch(revenueCatBootstrapProvider.future);
      yield* ref.read(purchaseCoordinatorProvider).watchCustomerInfo();
    });

final entitlementGuardProvider = Provider<EntitlementGuardService>((ref) {
  final subRepo = ref.watch(subscriptionRepositoryProvider);
  final usageRepo = ref.watch(usageQuotaRepositoryProvider);
  return EntitlementGuardService(
    subscriptionRepository: subRepo,
    usageQuotaRepository: usageRepo,
  );
});

final subscriptionStreamProvider =
    StreamProvider.family<SubscriptionState, String>((ref, workspaceId) {
      final repo = ref.watch(subscriptionRepositoryProvider);
      return repo.watchSubscription(workspaceId);
    });

final currentSubscriptionStreamProvider = StreamProvider<SubscriptionState>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return Stream.value(SubscriptionState.free());
  }
  final repo = ref.watch(subscriptionRepositoryProvider);
  return repo.watchSubscription(workspaceId);
});

final currentUsageProvider = StreamProvider<UsageSnapshot>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final subAsync = ref.watch(currentSubscriptionStreamProvider);

  final sub = subAsync.value ?? SubscriptionState.free();
  final limits = sub.isActiveOrTrial && sub.tier == PlanTier.pro
      ? PlanLimits.pro()
      : PlanLimits.free();

  if (workspaceId == null || workspaceId.isEmpty) {
    return Stream.value(UsageSnapshot.empty(limits: limits));
  }
  final repo = ref.watch(usageQuotaRepositoryProvider);
  return repo.watchUsageSnapshot(workspaceId: workspaceId, limits: limits);
});

class QuotaRequest {
  const QuotaRequest({
    required this.workspaceId,
    required this.type,
    this.delta = 1,
  });

  final String workspaceId;
  final LimitType type;
  final int delta;
}

final limitCheckProvider =
    FutureProvider.family<LimitCheckResult, QuotaRequest>((ref, request) async {
      final guard = ref.watch(entitlementGuardProvider);
      return guard.checkQuota(
        workspaceId: request.workspaceId,
        type: request.type,
        delta: request.delta,
      );
    });
