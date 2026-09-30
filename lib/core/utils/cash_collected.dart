import 'package:buildtrack_app/core/constants/payment_statuses.dart';

/// Cash actually received from a client payment.
///
/// Unpaid, refunded, and cancelled records contribute nothing. Partial
/// records use [paidAmount] when present, otherwise the full [amount]
/// (legacy docs that marked `partial` without a paid split). Missing
/// [paymentStatus] is treated as paid, matching [PaymentRecord.fromMap].
/// Round to currency minor units (2 decimals) for display and aggregation.
double roundMoney(double value) {
  if (!value.isFinite) {
    return 0;
  }
  return (value * 100).round() / 100;
}

double cashCollectedAmount({
  required double amount,
  String? paymentStatus,
  double? paidAmount,
}) {
  if (!amount.isFinite || amount <= 0) {
    return 0;
  }
  final status = (paymentStatus ?? PaymentStatuses.paid).trim().toLowerCase();
  switch (status) {
    case PaymentStatuses.unpaid:
    case PaymentStatuses.refunded:
    case PaymentStatuses.cancelled:
      return 0;
    case PaymentStatuses.partial:
      if (paidAmount != null && paidAmount > 0) {
        return roundMoney(paidAmount < amount ? paidAmount : amount);
      }
      return roundMoney(amount);
    default:
      return roundMoney(amount);
  }
}
