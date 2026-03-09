class Expense {
  const Expense({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.category,
    required this.amount,
    required this.date,
    required this.notes,
    required this.supplierName,
    required this.paymentMethod,
    required this.isArchived,
  });

  final String id;
  final String workspaceId;
  final String projectId;
  final String category;
  final double amount;
  final DateTime date;
  final String notes;
  final String supplierName;
  final String paymentMethod;
  final bool isArchived;

  factory Expense.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) {
        return value;
      }
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      if (value != null) {
        try {
          return (value as dynamic).toDate() as DateTime;
        } catch (_) {
          // ignored
        }
      }
      return DateTime.now();
    }

    return Expense(
      id: id,
      workspaceId: map['workspaceId'] as String? ?? '',
      projectId: map['projectId'] as String? ?? '',
      category: map['category'] as String? ?? 'other',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      date: parseDate(map['date']),
      notes: map['notes'] as String? ?? '',
      supplierName: map['supplierName'] as String? ?? '',
      paymentMethod: map['paymentMethod'] as String? ?? '',
      isArchived: map['isArchived'] as bool? ?? false,
    );
  }
}
