import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses paidAmount and treats unpaid as zero cash collected', () {
    final unpaid = PaymentRecord.fromMap('p1', {
      'workspaceId': 'ws',
      'projectId': 'pr',
      'amount': 10000,
      'date': DateTime.utc(2026, 6, 1),
      'paymentMethod': 'cash',
      'paymentStatus': PaymentStatuses.unpaid,
      'notes': '',
      'attachments': <dynamic>[],
      'isArchived': false,
    });
    expect(unpaid.paidAmount, isNull);
    expect(unpaid.cashCollected, 0);

    final partial = PaymentRecord.fromMap('p2', {
      'workspaceId': 'ws',
      'projectId': 'pr',
      'amount': 2000,
      'paidAmount': 750,
      'date': DateTime.utc(2026, 6, 1),
      'paymentMethod': 'cash',
      'paymentStatus': PaymentStatuses.partial,
      'notes': '',
      'attachments': <dynamic>[],
      'isArchived': false,
    });
    expect(partial.paidAmount, 750);
    expect(partial.cashCollected, 750);
  });
}
