class ProjectAccountingSummary {
  const ProjectAccountingSummary({
    required this.workspaceId,
    this.projectId,
    this.todayExpenses = 0,
    this.weeklyExpenses = 0,
    this.monthlyExpenses = 0,
    this.transactionCount = 0,
    this.totalPayments = 0,
    this.attachmentCount = 0,
    required this.updatedAt,
  });

  final String workspaceId;
  final String? projectId;
  final double todayExpenses;
  final double weeklyExpenses;
  final double monthlyExpenses;
  final int transactionCount;
  final double totalPayments;
  final int attachmentCount;
  final DateTime updatedAt;

  factory ProjectAccountingSummary.fromMap(Map<String, dynamic> map) {
    return ProjectAccountingSummary(
      workspaceId: map['workspaceId'] as String? ?? '',
      projectId: _optionalString(map['projectId']),
      todayExpenses: _doubleValue(map['todayExpenses']),
      weeklyExpenses: _doubleValue(map['weeklyExpenses']),
      monthlyExpenses: _doubleValue(map['monthlyExpenses']),
      transactionCount: _intValue(map['transactionCount']),
      totalPayments: _doubleValue(map['totalPayments']),
      attachmentCount: _intValue(map['attachmentCount']),
      updatedAt: _dateValue(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'workspaceId': workspaceId,
    if (projectId != null && projectId!.isNotEmpty) 'projectId': projectId,
    'todayExpenses': todayExpenses,
    'weeklyExpenses': weeklyExpenses,
    'monthlyExpenses': monthlyExpenses,
    'transactionCount': transactionCount,
    'totalPayments': totalPayments,
    'attachmentCount': attachmentCount,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class EntityAccountingSummary {
  const EntityAccountingSummary({
    required this.workspaceId,
    this.projectId,
    required this.entityId,
    required this.entityName,
    required this.entityType,
    this.totalExpenses = 0,
    this.totalPayments = 0,
    this.totalPaid = 0,
    this.remainingBalance = 0,
    this.transactionCount = 0,
    this.attachmentCount = 0,
    required this.latestTransactionDate,
    this.categoryBreakdown = const {},
    this.paymentMethodBreakdown = const {},
    required this.updatedAt,
  });

  final String workspaceId;
  final String? projectId;
  final String entityId;
  final String entityName;
  final String entityType;
  final double totalExpenses;
  final double totalPayments;
  final double totalPaid;
  final double remainingBalance;
  final int transactionCount;
  final int attachmentCount;
  final DateTime latestTransactionDate;
  final Map<String, double> categoryBreakdown;
  final Map<String, double> paymentMethodBreakdown;
  final DateTime updatedAt;

  factory EntityAccountingSummary.fromMap(Map<String, dynamic> map) {
    return EntityAccountingSummary(
      workspaceId: map['workspaceId'] as String? ?? '',
      projectId: _optionalString(map['projectId']),
      entityId: map['entityId'] as String? ?? '',
      entityName: map['entityName'] as String? ?? '',
      entityType: map['entityType'] as String? ?? '',
      totalExpenses: _doubleValue(map['totalExpenses']),
      totalPayments: _doubleValue(map['totalPayments']),
      totalPaid: _doubleValue(map['totalPaid']),
      remainingBalance: _doubleValue(map['remainingBalance']),
      transactionCount: _intValue(map['transactionCount']),
      attachmentCount: _intValue(map['attachmentCount']),
      latestTransactionDate: _dateValue(map['latestTransactionDate']),
      categoryBreakdown: _doubleMap(map['categoryBreakdown']),
      paymentMethodBreakdown: _doubleMap(map['paymentMethodBreakdown']),
      updatedAt: _dateValue(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'workspaceId': workspaceId,
    if (projectId != null && projectId!.isNotEmpty) 'projectId': projectId,
    'entityId': entityId,
    'entityName': entityName,
    'entityType': entityType,
    'totalExpenses': totalExpenses,
    'totalPayments': totalPayments,
    'totalPaid': totalPaid,
    'remainingBalance': remainingBalance,
    'transactionCount': transactionCount,
    'attachmentCount': attachmentCount,
    'latestTransactionDate': latestTransactionDate.toIso8601String(),
    'categoryBreakdown': categoryBreakdown,
    'paymentMethodBreakdown': paymentMethodBreakdown,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class CategoryAccountingSummary {
  const CategoryAccountingSummary({
    required this.workspaceId,
    this.projectId,
    required this.category,
    this.totalAmount = 0,
    this.transactionCount = 0,
    required this.latestTransactionDate,
    required this.updatedAt,
  });

  final String workspaceId;
  final String? projectId;
  final String category;
  final double totalAmount;
  final int transactionCount;
  final DateTime latestTransactionDate;
  final DateTime updatedAt;

  factory CategoryAccountingSummary.fromMap(Map<String, dynamic> map) {
    return CategoryAccountingSummary(
      workspaceId: map['workspaceId'] as String? ?? '',
      projectId: _optionalString(map['projectId']),
      category: map['category'] as String? ?? '',
      totalAmount: _doubleValue(map['totalAmount']),
      transactionCount: _intValue(map['transactionCount']),
      latestTransactionDate: _dateValue(map['latestTransactionDate']),
      updatedAt: _dateValue(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'workspaceId': workspaceId,
    if (projectId != null && projectId!.isNotEmpty) 'projectId': projectId,
    'category': category,
    'totalAmount': totalAmount,
    'transactionCount': transactionCount,
    'latestTransactionDate': latestTransactionDate.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class WeeklyAccountingSummary {
  const WeeklyAccountingSummary({
    required this.workspaceId,
    this.projectId,
    required this.weekStart,
    required this.weekEnd,
    this.totalExpenses = 0,
    this.totalPayments = 0,
    this.topEntity = const {},
    this.topCategory = const {},
    this.laborSummary = const {},
    this.equipmentSummary = const {},
    this.paymentSummary = const {},
    this.recentTransactionRefs = const [],
    required this.updatedAt,
  });

  final String workspaceId;
  final String? projectId;
  final DateTime weekStart;
  final DateTime weekEnd;
  final double totalExpenses;
  final double totalPayments;
  final Map<String, dynamic> topEntity;
  final Map<String, dynamic> topCategory;
  final Map<String, dynamic> laborSummary;
  final Map<String, dynamic> equipmentSummary;
  final Map<String, dynamic> paymentSummary;
  final List<String> recentTransactionRefs;
  final DateTime updatedAt;

  factory WeeklyAccountingSummary.fromMap(Map<String, dynamic> map) {
    return WeeklyAccountingSummary(
      workspaceId: map['workspaceId'] as String? ?? '',
      projectId: _optionalString(map['projectId']),
      weekStart: _dateValue(map['weekStart']),
      weekEnd: _dateValue(map['weekEnd']),
      totalExpenses: _doubleValue(map['totalExpenses']),
      totalPayments: _doubleValue(map['totalPayments']),
      topEntity: _dynamicMap(map['topEntity']),
      topCategory: _dynamicMap(map['topCategory']),
      laborSummary: _dynamicMap(map['laborSummary']),
      equipmentSummary: _dynamicMap(map['equipmentSummary']),
      paymentSummary: _dynamicMap(map['paymentSummary']),
      recentTransactionRefs: _stringList(map['recentTransactionRefs']),
      updatedAt: _dateValue(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'workspaceId': workspaceId,
    if (projectId != null && projectId!.isNotEmpty) 'projectId': projectId,
    'weekStart': weekStart.toIso8601String(),
    'weekEnd': weekEnd.toIso8601String(),
    'totalExpenses': totalExpenses,
    'totalPayments': totalPayments,
    'topEntity': topEntity,
    'topCategory': topCategory,
    'laborSummary': laborSummary,
    'equipmentSummary': equipmentSummary,
    'paymentSummary': paymentSummary,
    'recentTransactionRefs': recentTransactionRefs,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

String? _optionalString(Object? raw) {
  final value = raw as String?;
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

double _doubleValue(Object? raw) => raw is num ? raw.toDouble() : 0;

int _intValue(Object? raw) => raw is num ? raw.toInt() : 0;

DateTime _dateValue(Object? raw) {
  if (raw is DateTime) {
    return raw;
  }
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

Map<String, double> _doubleMap(Object? raw) {
  if (raw is! Map) {
    return const {};
  }
  return raw.map((key, value) => MapEntry(key.toString(), _doubleValue(value)));
}

Map<String, dynamic> _dynamicMap(Object? raw) {
  if (raw is! Map) {
    return const {};
  }
  return Map<String, dynamic>.from(raw);
}

List<String> _stringList(Object? raw) {
  if (raw is! Iterable) {
    return const [];
  }
  return raw.map((item) => item.toString()).toList(growable: false);
}
