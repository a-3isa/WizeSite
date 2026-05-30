class PaymentStatuses {
  const PaymentStatuses._();

  static const unpaid = 'unpaid';
  static const partial = 'partial';
  static const paid = 'paid';
  static const refunded = 'refunded';
  static const cancelled = 'cancelled';

  static const values = <String>[
    unpaid,
    partial,
    paid,
    refunded,
    cancelled,
  ];
}
