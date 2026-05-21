import 'package:buildtrack_app/features/subscription/domain/entitlement_guard_service.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_repository.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_quota_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSubscriptionRepository implements SubscriptionRepository {
  _FakeSubscriptionRepository(this.state);

  SubscriptionState state;

  @override
  Future<SubscriptionState> getSubscription(String workspaceId) async => state;

  @override
  Stream<SubscriptionState> watchSubscription(String workspaceId) =>
      Stream.value(state);
}

class _FakeUsageRepository implements UsageQuotaRepository {
  _FakeUsageRepository(this.result);

  LimitCheckResult result;

  @override
  Future<LimitCheckResult> checkLimit({
    required String workspaceId,
    required LimitType type,
    required int delta,
  }) async {
    return result;
  }

  @override
  Future<UsageSnapshot> getUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) async {
    return UsageSnapshot.empty(limits: limits);
  }

  @override
  Stream<UsageSnapshot> watchUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) {
    return Stream.value(UsageSnapshot.empty(limits: limits));
  }
}

void main() {
  group('EntitlementGuardService', () {
    test('allows quota automatically for active pro users', () async {
      final subRepo = _FakeSubscriptionRepository(
        SubscriptionState(
          tier: PlanTier.pro,
          status: SubscriptionStatus.active,
          store: 'app_store',
          isAutoRenewing: true,
          lastSyncedAt: DateTime.now(),
        ),
      );
      final usageRepo = _FakeUsageRepository(
        const LimitCheckResult(
          allowed: false,
          limitType: LimitType.expensesPerMonth,
          current: 30,
          max: 30,
        ),
      );
      final service = EntitlementGuardService(
        subscriptionRepository: subRepo,
        usageQuotaRepository: usageRepo,
      );

      final result = await service.checkQuota(
        workspaceId: 'w1',
        type: LimitType.expensesPerMonth,
      );
      expect(result.allowed, isTrue);
      expect(result.max, 999999);
    });

    test('allows quota while usage limits are disabled', () async {
      final subRepo = _FakeSubscriptionRepository(
        SubscriptionState(
          tier: PlanTier.free,
          status: SubscriptionStatus.expired,
          store: 'none',
          isAutoRenewing: false,
          lastSyncedAt: DateTime.now(),
        ),
      );
      final usageRepo = _FakeUsageRepository(
        const LimitCheckResult(
          allowed: false,
          limitType: LimitType.expensesPerMonth,
          current: 30,
          max: 30,
        ),
      );
      final service = EntitlementGuardService(
        subscriptionRepository: subRepo,
        usageQuotaRepository: usageRepo,
      );

      final result = await service.checkQuota(
        workspaceId: 'w1',
        type: LimitType.expensesPerMonth,
      );

      expect(result.allowed, isTrue);
    });
  });
}
