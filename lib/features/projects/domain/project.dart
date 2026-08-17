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

  /// The agreed amount the client pays. `null` when no contract has been
  /// agreed — the project is then a pure expense ledger.
  ///
  /// Absence is deliberately modelled as `null` rather than `0`, mirroring
  /// [budgetLimit], so a placeholder zero can never be mistaken for a real
  /// agreed amount.
  final double? contractValue;
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

  /// Whether a real contract amount has been agreed for this project.
  ///
  /// Zero counts as absent: the server already collapses `0` to `null`, and a
  /// zero-value contract has no meaning in this domain.
  bool get hasContractValue => contractValue != null && contractValue! > 0;

  /// The amount spending is measured against: the [budgetLimit] when one is
  /// set, otherwise the [contractValue]. `null` when neither exists.
  ///
  /// This is the single definition of the rule. It previously existed as three
  /// divergent copies across the detail screen, the dashboard, and the project
  /// list; every surface must read it from here so they cannot drift apart.
  double? get budgetBase {
    final limit = budgetLimit;
    if (limit != null && limit > 0) {
      return limit;
    }
    return hasContractValue ? contractValue : null;
  }

  /// Whether budget-usage widgets (progress bar, percentage used, remaining,
  /// over-budget state) have a baseline to render against.
  bool get hasBudget {
    final base = budgetBase;
    return base != null && base > 0;
  }

  /// Whether an explicit spending ceiling was set, ignoring any contract
  /// fallback.
  ///
  /// Distinct from [hasBudget] on purpose. The project list card has always
  /// shown its budget bar only for an explicit Budget Limit, and FR-018
  /// requires contract-bearing projects to look exactly as they do today — so
  /// the card must not start showing a bar for contract-only projects. This
  /// keeps that narrower rule on the model instead of inline in the widget.
  bool get hasBudgetLimit => budgetLimit != null && budgetLimit! > 0;

  /// Whether the project reads as a pure cost tracker, with the revenue side
  /// hidden.
  ///
  /// Governed by the contract alone — independent of [hasBudget]. A project may
  /// have a Budget Limit and still be in this mode: a spending budget with no
  /// income expected. By the core invariant, a project in this mode can never
  /// hold payments.
  bool get isExpenseLedger => !hasContractValue;

  /// Reads an optional money field, collapsing both a missing value and a
  /// stored zero to `null`. Zero and absent mean the same thing in this domain,
  /// and normalizing at the boundary means no consumer has to check for both.
  static double? _optionalAmount(dynamic value) {
    final amount = (value as num?)?.toDouble();
    if (amount == null || amount == 0) {
      return null;
    }
    return amount;
  }

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
      // Deliberately no `?? 0` fallback: a fake zero here would defeat every
      // adaptive widget downstream, which is the bug this field exists to fix.
      // A stored zero is normalized to null too — zero and absent mean the
      // same thing, and collapsing them here means no consumer has to know.
      contractValue: _optionalAmount(map['contractValue']),
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
      budgetLimit: _optionalAmount(map['budgetLimit']),
      startDate: _parseDate(map['startDate']),
      expectedEndDate: _parseDate(map['expectedEndDate']),
    );
  }
}
