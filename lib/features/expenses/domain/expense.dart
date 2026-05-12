class Expense {
  const Expense({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.projectName,
    required this.category,
    required this.amount,
    required this.currency,
    required this.date,
    required this.notes,
    required this.supplierName,
    required this.paymentMethod,
    required this.inputMethod,
    required this.transcript,
    required this.source,
    required this.storagePath,
    required this.isArchived,
  });

  final String id;
  final String workspaceId;
  final String projectId;
  final String projectName;
  final String category;
  final double amount;
  final String currency;
  final DateTime date;
  final String notes;
  final String supplierName;
  final String paymentMethod;
  final String inputMethod;
  final String transcript;
  final String source;
  final String storagePath;
  final bool isArchived;

  factory Expense.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) {
        return value;
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
        throw FormatException('Invalid expense date for $id: $value');
      }
      if (value != null) {
        try {
          final converted = (value as dynamic).toDate();
          if (converted is DateTime) {
            return converted;
          }
        } catch (_) {
          // ignored
        }
      }
      throw FormatException('Missing expense date for $id');
    }

    return Expense(
      id: id,
      workspaceId: map['workspaceId'] as String? ?? '',
      projectId: map['projectId'] as String? ?? '',
      projectName: map['projectName'] as String? ?? '',
      category: map['category'] as String? ?? 'other',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] as String? ?? 'EGP',
      date: parseDate(map['date']),
      notes: map['notes'] as String? ?? '',
      supplierName: map['supplierName'] as String? ?? '',
      paymentMethod: map['paymentMethod'] as String? ?? '',
      inputMethod: map['inputMethod'] as String? ?? 'manual',
      transcript: map['transcript'] as String? ?? '',
      source: map['source'] as String? ?? '',
      storagePath: map['storagePath'] as String? ?? '',
      isArchived: map['isArchived'] as bool? ?? false,
    );
  }
}
