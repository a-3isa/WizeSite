class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.amount,
    required this.date,
    required this.paymentMethod,
    required this.notes,
    required this.isArchived,
  });

  final String id;
  final String workspaceId;
  final String projectId;
  final double amount;
  final DateTime date;
  final String paymentMethod;
  final String notes;
  final bool isArchived;

  factory PaymentRecord.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) {
        return value;
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
        throw FormatException('Invalid payment date for $id: $value');
      }
      if (value != null) {
        try {
          final converted = (value as dynamic).toDate();
          if (converted is DateTime) {
            return converted;
          }
        } catch (_) {}
      }
      throw FormatException('Missing payment date for $id');
    }

    return PaymentRecord(
      id: id,
      workspaceId: map['workspaceId'] as String? ?? '',
      projectId: map['projectId'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      date: parseDate(map['date']),
      paymentMethod: map['paymentMethod'] as String? ?? 'cash',
      notes: map['notes'] as String? ?? '',
      isArchived: map['isArchived'] as bool? ?? false,
    );
  }
}
