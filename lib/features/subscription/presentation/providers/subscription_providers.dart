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

final currentSubscriptionProvider = FutureProvider<SubscriptionState>((
  ref,
) async {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return SubscriptionState.free();
  }
  final repo = ref.watch(subscriptionRepositoryProvider);
  return repo.getSubscription(workspaceId);
});

final currentUsageProvider = FutureProvider<UsageSnapshot>((ref) async {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final sub = await ref.watch(currentSubscriptionProvider.future);

  final limits = sub.isActiveOrTrial && sub.tier == PlanTier.pro
      ? PlanLimits.pro()
      : PlanLimits.free();

  if (workspaceId == null || workspaceId.isEmpty) {
    return UsageSnapshot.empty(limits: limits);
  }
  final repo = ref.watch(usageQuotaRepositoryProvider);
  return repo.getUsageSnapshot(workspaceId: workspaceId, limits: limits);
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
