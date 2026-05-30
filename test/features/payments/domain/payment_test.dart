import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses structured payment fields', () {
    final payment = PaymentRecord.fromMap('payment_1', {
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'amount': 900,
      'date': '2026-05-27T00:00:00.000Z',
      'paymentMethod': 'bank',
      'paymentStatus': PaymentStatuses.paid,
      'description': 'Client milestone payment',
      'notes': 'Invoice 12',
      'entityId': 'entity_1',
      'entityName': 'Client LLC',
      'entityType': 'other',
    });

    expect(payment.paymentStatus, PaymentStatuses.paid);
    expect(payment.description, 'Client milestone payment');
    expect(payment.entityType, 'other');
  });

  test('uses backward-compatible defaults for old payment records', () {
    final payment = PaymentRecord.fromMap('payment_legacy', {
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'amount': 300,
      'date': '2026-05-27T00:00:00.000Z',
      'notes': 'Legacy payment note',
      'entityName': 'Legacy Client',
    });

    expect(payment.paymentMethod, 'cash');
    expect(payment.paymentStatus, PaymentStatuses.paid);
    expect(payment.description, 'Legacy payment note');
    expect(payment.entityType, 'other');
  });
}
