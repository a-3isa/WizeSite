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

  factory Project.fromMap(String id, Map<String, dynamic> map) {
    return Project(
      id: id,
      workspaceId: map['workspaceId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      clientName: map['clientName'] as String? ?? '',
      contractValue: (map['contractValue'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'active',
      completionPercentage:
          (map['completionPercentage'] as num?)?.toDouble() ?? 0,
      totalExpenses: (map['totalExpenses'] as num?)?.toDouble() ?? 0,
      totalPayments: (map['totalPayments'] as num?)?.toDouble() ?? 0,
      netProfit: (map['netProfit'] as num?)?.toDouble() ?? 0,
      isArchived: map['isArchived'] as bool? ?? false,
    );
  }
}
