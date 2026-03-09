import 'package:buildtrack_app/core/constants/app_limits.dart';

enum LimitType {
  activeProjects,
  expensesPerMonth,
  paymentsPerMonth,
  workerEntriesPerMonth,
  teamMembers,
}

class PlanLimits {
  const PlanLimits({
    required this.activeProjects,
    required this.expensesPerMonth,
    required this.paymentsPerMonth,
    required this.workerEntriesPerMonth,
    required this.teamMembers,
  });

  final int activeProjects;
  final int expensesPerMonth;
  final int paymentsPerMonth;
  final int workerEntriesPerMonth;
  final int teamMembers;

  factory PlanLimits.free() {
    return const PlanLimits(
      activeProjects: AppLimits.freeActiveProjects,
      expensesPerMonth: AppLimits.freeExpensesPerMonth,
      paymentsPerMonth: AppLimits.freePaymentsPerMonth,
      workerEntriesPerMonth: AppLimits.freeWorkerEntriesPerMonth,
      teamMembers: AppLimits.freeTeamMembers,
    );
  }

  factory PlanLimits.pro() {
    return const PlanLimits(
      activeProjects: AppLimits.proLimit,
      expensesPerMonth: AppLimits.proLimit,
      paymentsPerMonth: AppLimits.proLimit,
      workerEntriesPerMonth: AppLimits.proLimit,
      teamMembers: AppLimits.proLimit,
    );
  }
}

class UsageSnapshot {
  const UsageSnapshot({
    required this.periodKey,
    required this.activeProjects,
    required this.expensesCount,
    required this.paymentsCount,
    required this.workerEntriesCount,
    required this.memberCount,
    required this.limits,
  });

  final String periodKey;
  final int activeProjects;
  final int expensesCount;
  final int paymentsCount;
  final int workerEntriesCount;
  final int memberCount;
  final PlanLimits limits;

  factory UsageSnapshot.empty({required PlanLimits limits}) {
    return UsageSnapshot(
      periodKey: '',
      activeProjects: 0,
      expensesCount: 0,
      paymentsCount: 0,
      workerEntriesCount: 0,
      memberCount: 1,
      limits: limits,
    );
  }

  int currentByType(LimitType type) {
    switch (type) {
      case LimitType.activeProjects:
        return activeProjects;
      case LimitType.expensesPerMonth:
        return expensesCount;
      case LimitType.paymentsPerMonth:
        return paymentsCount;
      case LimitType.workerEntriesPerMonth:
        return workerEntriesCount;
      case LimitType.teamMembers:
        return memberCount;
    }
  }

  int maxByType(LimitType type) {
    switch (type) {
      case LimitType.activeProjects:
        return limits.activeProjects;
      case LimitType.expensesPerMonth:
        return limits.expensesPerMonth;
      case LimitType.paymentsPerMonth:
        return limits.paymentsPerMonth;
      case LimitType.workerEntriesPerMonth:
        return limits.workerEntriesPerMonth;
      case LimitType.teamMembers:
        return limits.teamMembers;
    }
  }
}

class LimitCheckResult {
  const LimitCheckResult({
    required this.allowed,
    required this.limitType,
    required this.current,
    required this.max,
    this.resetAt,
  });

  final bool allowed;
  final LimitType limitType;
  final int current;
  final int max;
  final DateTime? resetAt;
}

class LimitExceeded implements Exception {
  const LimitExceeded({
    required this.limitType,
    required this.current,
    required this.max,
  });

  final LimitType limitType;
  final int current;
  final int max;

  @override
  String toString() {
    return 'LimitExceeded(type: $limitType, current: $current, max: $max)';
  }
}
