import 'package:buildtrack_app/core/models/attachment.dart';

class ContractorAccountingRecord {
  const ContractorAccountingRecord({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.contractorId,
    required this.contractorName,
    required this.description,
    required this.amount,
    required this.date,
    required this.paymentMethod,
    required this.paymentStatus,
    this.notes = '',
    this.attachments = const [],
  });

  final String id;
  final String workspaceId;
  final String projectId;
  final String contractorId;
  final String contractorName;
  final String description;
  final double amount;
  final DateTime date;
  final String paymentMethod;
  final String paymentStatus;
  final String notes;
  final List<Attachment> attachments;

  factory ContractorAccountingRecord.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    return ContractorAccountingRecord(
      id: id,
      workspaceId: '${map['workspaceId'] ?? ''}',
      projectId: '${map['projectId'] ?? ''}',
      contractorId: '${map['contractorId'] ?? ''}',
      contractorName: '${map['contractorName'] ?? ''}',
      description: '${map['description'] ?? ''}',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      date: _parseDate(map['date']),
      paymentMethod: '${map['paymentMethod'] ?? ''}',
      paymentStatus: '${map['paymentStatus'] ?? ''}',
      notes: '${map['notes'] ?? ''}',
      attachments: Attachment.listFromDynamic(map['attachments']),
    );
  }

  Map<String, dynamic> toMap() => {
    'workspaceId': workspaceId,
    'projectId': projectId,
    'contractorId': contractorId,
    'contractorName': contractorName,
    'description': description,
    'amount': amount,
    'date': date,
    'paymentMethod': paymentMethod,
    'paymentStatus': paymentStatus,
    'notes': notes,
    'attachments': attachments.map((attachment) => attachment.toMap()).toList(),
  };
}

DateTime _parseDate(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
  return DateTime.now();
}
