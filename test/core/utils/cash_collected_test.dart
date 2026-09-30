import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/core/utils/cash_collected.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cashCollectedAmount', () {
    test('non-finite amounts contribute nothing', () {
      expect(cashCollectedAmount(amount: double.nan), 0);
      expect(cashCollectedAmount(amount: double.infinity), 0);
    });

    test('paid counts the full amount', () {
      expect(
        cashCollectedAmount(amount: 10000, paymentStatus: PaymentStatuses.paid),
        10000,
      );
    });

    test('unpaid contributes nothing', () {
      expect(
        cashCollectedAmount(amount: 3000, paymentStatus: PaymentStatuses.unpaid),
        0,
      );
    });

    test('refunded and cancelled contribute nothing', () {
      expect(
        cashCollectedAmount(
          amount: 400,
          paymentStatus: PaymentStatuses.refunded,
        ),
        0,
      );
      expect(
        cashCollectedAmount(
          amount: 400,
          paymentStatus: PaymentStatuses.cancelled,
        ),
        0,
      );
    });

    test('partial without paidAmount counts the full amount', () {
      expect(
        cashCollectedAmount(
          amount: 2000,
          paymentStatus: PaymentStatuses.partial,
        ),
        2000,
      );
    });

    test('partial with paidAmount counts only the paid split', () {
      expect(
        cashCollectedAmount(
          amount: 2000,
          paymentStatus: PaymentStatuses.partial,
          paidAmount: 750,
        ),
        750,
      );
    });

    test('rounds paid cash to two decimal places', () {
      expect(
        cashCollectedAmount(amount: 10.129, paymentStatus: PaymentStatuses.paid),
        10.13,
      );
    });
  });
}
