import 'package:buildtrack_app/core/models/attachment.dart';

class WorkerAccountingRecord {
  const WorkerAccountingRecord({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.workerId,
    required this.workerName,
    required this.description,
    required this.amount,
    required this.date,
    required this.paymentMethod,
    required this.paymentStatus,
    this.paidAmount,
    this.notes = '',
    this.attachments = const [],
  });

  final String id;
  final String workspaceId;
  final String projectId;
  final String workerId;
  final String workerName;
  final String description;
  final double amount;
  final DateTime date;
  final String paymentMethod;
  final String paymentStatus;

  /// Amount actually paid for a `partial` record. Null on legacy partial
  /// records that predate this field (their true paid amount is unknown).
  final double? paidAmount;
  final String notes;
  final List<Attachment> attachments;

  bool get isPartial => paymentStatus == 'partial';

  /// True when a `partial` record's paid portion cannot be confirmed (a legacy
  /// record with no [paidAmount], or an out-of-range/invalid amount), so it is
  /// excluded from confirmed totals. Matches the backend recompute, which counts
  /// the same cases under `unresolvedLegacyCount`.
  bool get isLegacyPartialUnresolved =>
      isPartial && confirmedPaidAmount == null;

  /// The confirmed amount paid, or null when it cannot be determined (an
  /// unresolved legacy partial: missing or out-of-range `paidAmount`).
  double? get confirmedPaidAmount {
    switch (paymentStatus) {
      case 'paid':
        return amount;
      case 'unpaid':
        return 0;
      case 'partial':
        final paid = paidAmount;
        // Missing or out-of-range partials are not trustworthy → unresolved
        // (never fabricated by clamping), consistent with the functions writer.
        if (paid == null || paid <= 0 || paid >= amount) return null;
        return paid;
      default:
        return null;
    }
  }

  /// Amount still owed, or null when the paid portion is unresolved.
  double? get outstandingAmount {
    final paid = confirmedPaidAmount;
    return paid == null ? null : amount - paid;
  }

  /// Validates a `partial` record's [paidAmount]. Returns a localization key
  /// describing the problem, or null when valid. Non-partial statuses never
  /// require a paid amount.
  static String? validatePaidAmount({
    required String paymentStatus,
    required double amount,
    required double? paidAmount,
  }) {
    if (paymentStatus != 'partial') return null;
    if (paidAmount == null) return 'workerPaidAmountRequired';
    if (paidAmount <= 0) return 'workerPaidAmountTooLow';
    if (paidAmount >= amount) return 'workerPaidAmountTooHigh';
    return null;
  }

  factory WorkerAccountingRecord.fromMap(String id, Map<String, dynamic> map) {
    return WorkerAccountingRecord(
      id: id,
      workspaceId: '${map['workspaceId'] ?? ''}',
      projectId: '${map['projectId'] ?? ''}',
      workerId: '${map['workerId'] ?? ''}',
      workerName: '${map['workerName'] ?? ''}',
      description: '${map['description'] ?? ''}',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      date: _parseDate(map['date']),
      paymentMethod: '${map['paymentMethod'] ?? ''}',
      paymentStatus: '${map['paymentStatus'] ?? ''}',
      paidAmount: (map['paidAmount'] as num?)?.toDouble(),
      notes: '${map['notes'] ?? ''}',
      attachments: Attachment.listFromDynamic(map['attachments']),
    );
  }

  Map<String, dynamic> toMap() => {
    'workspaceId': workspaceId,
    'projectId': projectId,
    'workerId': workerId,
    'workerName': workerName,
    'description': description,
    'amount': amount,
    'date': date,
    'paymentMethod': paymentMethod,
    'paymentStatus': paymentStatus,
    if (paidAmount != null) 'paidAmount': paidAmount,
    'notes': notes,
    'attachments': attachments.map((attachment) => attachment.toMap()).toList(),
  };
}

/// Confirmed aggregate over a set of worker accounting records. Unresolved
/// legacy partial records contribute their full [WorkerAccountingRecord.amount]
/// to [totalAmount] but are excluded from [confirmedPaid] / [confirmedOutstanding]
/// and counted in [unresolvedLegacyCount] so the UI can disclose them.
class WorkerAccountingTotals {
  const WorkerAccountingTotals({
    required this.confirmedPaid,
    required this.confirmedOutstanding,
    required this.totalAmount,
    required this.unresolvedLegacyCount,
  });

  final double confirmedPaid;
  final double confirmedOutstanding;
  final double totalAmount;
  final int unresolvedLegacyCount;

  bool get hasUnresolvedLegacy => unresolvedLegacyCount > 0;

  factory WorkerAccountingTotals.fromRecords(
    Iterable<WorkerAccountingRecord> records,
  ) {
    var paid = 0.0;
    var outstanding = 0.0;
    var total = 0.0;
    var unresolved = 0;
    for (final record in records) {
      total += record.amount;
      final confirmed = record.confirmedPaidAmount;
      if (confirmed == null) {
        unresolved += 1;
        continue;
      }
      paid += confirmed;
      outstanding += record.amount - confirmed;
    }
    return WorkerAccountingTotals(
      confirmedPaid: paid,
      confirmedOutstanding: outstanding,
      totalAmount: total,
      unresolvedLegacyCount: unresolved,
    );
  }
}

/// Maintained, exact aggregate over a worker's full accounting ledger, written
/// by a backend recompute so totals never depend on the visible page size.
class WorkerAccountingSummary {
  const WorkerAccountingSummary({
    required this.workspaceId,
    required this.workerId,
    required this.totalAmount,
    required this.confirmedPaid,
    required this.confirmedOutstanding,
    required this.unresolvedLegacyCount,
    required this.recordCount,
  });

  final String workspaceId;
  final String workerId;
  final double totalAmount;
  final double confirmedPaid;
  final double confirmedOutstanding;
  final int unresolvedLegacyCount;
  final int recordCount;

  bool get hasUnresolvedLegacy => unresolvedLegacyCount > 0;

  factory WorkerAccountingSummary.fromMap(String id, Map<String, dynamic> map) {
    return WorkerAccountingSummary(
      workspaceId: '${map['workspaceId'] ?? ''}',
      workerId: '${map['workerId'] ?? ''}',
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0,
      confirmedPaid: (map['confirmedPaid'] as num?)?.toDouble() ?? 0,
      confirmedOutstanding:
          (map['confirmedOutstanding'] as num?)?.toDouble() ?? 0,
      unresolvedLegacyCount:
          (map['unresolvedLegacyCount'] as num?)?.toInt() ?? 0,
      recordCount: (map['recordCount'] as num?)?.toInt() ?? 0,
    );
  }
}

DateTime _parseDate(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
  return DateTime.now();
}
