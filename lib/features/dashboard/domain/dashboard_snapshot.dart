class DashboardSnapshot {
  const DashboardSnapshot({
    required this.hasFinancialAccess,
    required this.totalProjects,
    required this.activeProjects,
    required this.totalExpenses,
    required this.totalIncome,
    required this.weeklyExpenses,
    required this.weeklyIncome,
    required this.topCategory,
    required this.topEntity,
    required this.recentTransactions,
  });

  final bool hasFinancialAccess;
  final int totalProjects;
  final int activeProjects;
  final double totalExpenses;
  final double totalIncome;
  final double weeklyExpenses;
  final double weeklyIncome;
  final String? topCategory;
  final String? topEntity;
  final List<DashboardTransactionRef> recentTransactions;

  double get net => totalIncome - totalExpenses;
  double get weeklyNet => weeklyIncome - weeklyExpenses;

  factory DashboardSnapshot.restricted() => const DashboardSnapshot(
    hasFinancialAccess: false,
    totalProjects: 0,
    activeProjects: 0,
    totalExpenses: 0,
    totalIncome: 0,
    weeklyExpenses: 0,
    weeklyIncome: 0,
    topCategory: null,
    topEntity: null,
    recentTransactions: [],
  );

  factory DashboardSnapshot.fromMap(Map<String, dynamic> data) {
    final recent = data['recentTransactions'];
    return DashboardSnapshot(
      hasFinancialAccess: true,
      totalProjects: ((data['totalProjects'] as num?) ?? 0).toInt(),
      activeProjects: ((data['activeProjects'] as num?) ?? 0).toInt(),
      totalExpenses: ((data['totalExpenses'] as num?) ?? 0).toDouble(),
      totalIncome: ((data['totalIncome'] as num?) ?? 0).toDouble(),
      weeklyExpenses: ((data['weeklyExpenses'] as num?) ?? 0).toDouble(),
      weeklyIncome: ((data['weeklyIncome'] as num?) ?? 0).toDouble(),
      topCategory: _optionalText(data['topCategory']),
      topEntity: _optionalText(data['topEntity']),
      recentTransactions: recent is List
          ? recent
                .whereType<Map<dynamic, dynamic>>()
                .map(
                  (item) => DashboardTransactionRef.fromMap(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .take(10)
                .toList(growable: false)
          : const [],
    );
  }

  static String? _optionalText(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }
}

class DashboardTransactionRef {
  const DashboardTransactionRef({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.date,
  });

  final String id;
  final String type;
  final String title;
  final double amount;
  final DateTime? date;

  factory DashboardTransactionRef.fromMap(Map<String, dynamic> data) {
    return DashboardTransactionRef(
      id: '${data['id'] ?? ''}',
      type: '${data['type'] ?? ''}',
      title: '${data['title'] ?? ''}',
      amount: ((data['amount'] as num?) ?? 0).toDouble(),
      date: DateTime.tryParse('${data['date'] ?? ''}'),
    );
  }
}
