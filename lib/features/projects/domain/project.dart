class Project {
  const Project({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.clientName,
    required this.contractValue,
    required this.status,
    required this.completionPercentage,
    required this.totalExpenses,
    required this.totalPayments,
    required this.netProfit,
    required this.isArchived,
    this.clientMutationId = '',
    this.location = '',
    this.description = '',
    this.budgetLimit,
    this.startDate,
    this.expectedEndDate,
  });

  final String id;
  final String workspaceId;
  final String name;
  final String clientName;
  final double contractValue;
  final String status;
  final double completionPercentage;
  final double totalExpenses;
  final double totalPayments;
  final double netProfit;
  final bool isArchived;
  final String clientMutationId;
  final String location;
  final String description;
  final double? budgetLimit;
  final DateTime? startDate;
  final DateTime? expectedEndDate;

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  factory Project.fromMap(String id, Map<String, dynamic> map) {
    final totalExpenses = (map['totalExpenses'] as num?)?.toDouble() ?? 0;
    final totalPayments =
        (map['totalPayments'] as num?)?.toDouble() ??
        (map['totalIncome'] as num?)?.toDouble() ??
        0;
    final netProfit =
        (map['netProfit'] as num?)?.toDouble() ??
        (map['net'] as num?)?.toDouble() ??
        totalPayments - totalExpenses;

    return Project(
      id: id,
      workspaceId: map['workspaceId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      clientName: map['clientName'] as String? ?? '',
      contractValue: (map['contractValue'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'active',
      completionPercentage:
          (map['completionPercentage'] as num?)?.toDouble() ?? 0,
      totalExpenses: totalExpenses,
      totalPayments: totalPayments,
      netProfit: netProfit,
      isArchived: map['isArchived'] as bool? ?? false,
      clientMutationId: map['clientMutationId'] as String? ?? '',
      location: map['location'] as String? ?? '',
      description: map['description'] as String? ?? '',
      budgetLimit: (map['budgetLimit'] as num?)?.toDouble(),
      startDate: _parseDate(map['startDate']),
      expectedEndDate: _parseDate(map['expectedEndDate']),
    );
  }
}
