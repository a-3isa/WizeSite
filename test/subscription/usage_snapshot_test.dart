import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UsageSnapshot resolves current and max by limit type', () {
    const limits = PlanLimits(
      activeProjects: 1,
      expensesPerMonth: 30,
      paymentsPerMonth: 10,
      workerEntriesPerMonth: 10,
      teamMembers: 1,
    );
    const usage = UsageSnapshot(
      periodKey: '202603',
      activeProjects: 1,
      expensesCount: 15,
      paymentsCount: 4,
      workerEntriesCount: 9,
      memberCount: 1,
      limits: limits,
    );

    expect(usage.currentByType(LimitType.expensesPerMonth), 15);
    expect(usage.maxByType(LimitType.expensesPerMonth), 30);
    expect(usage.currentByType(LimitType.activeProjects), 1);
    expect(usage.maxByType(LimitType.activeProjects), 1);
  });
}
