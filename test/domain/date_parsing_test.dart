import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Strict date parsing', () {
    test('Expense throws on invalid date values', () {
      expect(
        () => Expense.fromMap('expense_1', {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'projectName': 'Project',
          'category': 'materials',
          'amount': 120,
          'currency': 'EGP',
          'date': 'not-a-date',
          'isArchived': false,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('PaymentRecord throws on invalid date values', () {
      expect(
        () => PaymentRecord.fromMap('payment_1', {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'amount': 80,
          'date': 'invalid',
          'paymentMethod': 'cash',
          'isArchived': false,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('WorkerEntryRecord throws on invalid date values', () {
      expect(
        () => WorkerEntryRecord.fromMap('entry_1', {
          'workspaceId': 'workspace_1',
          'workerId': 'worker_1',
          'projectId': 'project_1',
          'daysWorked': 2,
          'dailyWage': 100,
          'totalCost': 200,
          'date': 'nope',
          'isArchived': false,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
