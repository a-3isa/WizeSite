import 'package:buildtrack_app/features/expenses/domain/expense_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracks active advanced expense filters', () {
    final filter = ExpenseFilter(
      projectId: 'project_1',
      entityId: 'entity_1',
      entityName: 'Steel Supplier',
      entityType: 'supplier',
      category: 'materials',
      paymentMethod: 'cash',
      paymentStatus: 'unpaid',
      searchText: 'invoice',
      startDate: DateTime.utc(2026, 5, 1),
      endDate: DateTime.utc(2026, 5, 31),
    );

    expect(filter.hasActiveFilters, isTrue);
    expect(filter.activeCount, 9);
  });

  test('clear returns an empty filter', () {
    final filter = const ExpenseFilter(
      projectId: 'project_1',
      category: 'materials',
    ).clear();

    expect(filter.hasActiveFilters, isFalse);
    expect(filter.activeCount, 0);
  });
}
