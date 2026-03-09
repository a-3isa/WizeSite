import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_repository.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_quota_repository.dart';

class EntitlementGuardService {
  EntitlementGuardService({
    required SubscriptionRepository subscriptionRepository,
    required UsageQuotaRepository usageQuotaRepository,
  }) : _subscriptionRepository = subscriptionRepository,
       _usageQuotaRepository = usageQuotaRepository;

  final SubscriptionRepository _subscriptionRepository;
  final UsageQuotaRepository _usageQuotaRepository;

  Future<LimitCheckResult> checkQuota({
    required String workspaceId,
    required LimitType type,
    int delta = 1,
  }) async {
    final subscription = await _subscriptionRepository.getSubscription(
      workspaceId,
    );
    if (subscription.isActiveOrTrial && subscription.tier == PlanTier.pro) {
      return LimitCheckResult(
        allowed: true,
        limitType: type,
        current: 0,
        max: 999999,
      );
    }
    return _usageQuotaRepository.checkLimit(
      workspaceId: workspaceId,
      type: type,
      delta: delta,
    );
  }

  Future<void> ensureCanCreate({
    required String workspaceId,
    required LimitType type,
    int delta = 1,
  }) async {
    final result = await checkQuota(
      workspaceId: workspaceId,
      type: type,
      delta: delta,
    );
    if (!result.allowed) {
      throw LimitExceeded(
        limitType: type,
        current: result.current,
        max: result.max,
      );
    }
  }
}
