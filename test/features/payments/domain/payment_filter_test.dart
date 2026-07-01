import 'package:buildtrack_app/features/payments/domain/payment_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracks active advanced payment filters', () {
    final filter = PaymentFilter(
      projectId: 'project_1',
      entityId: 'entity_1',
      entityName: 'Client A',
      entityType: 'customer',
      paymentMethod: 'bank',
      paymentStatus: 'paid',
      searchText: 'deposit',
      startDate: DateTime.utc(2026, 5, 1),
      endDate: DateTime.utc(2026, 5, 31),
    );

    expect(filter.hasActiveFilters, isTrue);
    expect(filter.activeCount, 8);
  });

  test('copyWith updates one field while preserving the rest', () {
    const filter = PaymentFilter(projectId: 'project_1');

    final updated = filter.copyWith(paymentStatus: 'paid');

    expect(updated.projectId, 'project_1');
    expect(updated.paymentStatus, 'paid');
    expect(updated.activeCount, 2);
  });
}
