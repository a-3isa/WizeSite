import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';

abstract interface class UsageQuotaRepository {
  Future<UsageSnapshot> getUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  });

  Future<LimitCheckResult> checkLimit({
    required String workspaceId,
    required LimitType type,
    required int delta,
  });
}
