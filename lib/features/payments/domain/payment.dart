import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.amount,
    required this.date,
    required this.paymentMethod,
    this.paymentStatus = PaymentStatuses.paid,
    this.description = '',
    required this.notes,
    this.entityId,
    this.entityName = '',
    this.entityType = '',
    required this.attachments,
    required this.isArchived,
    this.clientMutationId = '',
  });

  final String id;
  final String workspaceId;
  final String projectId;
  final double amount;
  final DateTime date;
  final String paymentMethod;
  final String paymentStatus;
  final String description;
  final String notes;
  final String? entityId;
  final String entityName;
  final String entityType;
  final List<Attachment> attachments;
  final bool isArchived;
  final String clientMutationId;

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
      paymentStatus: map['paymentStatus'] as String? ?? PaymentStatuses.paid,
      description:
          map['description'] as String? ?? map['notes'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      entityId: map['entityId'] as String?,
      entityName: map['entityName'] as String? ?? '',
      entityType: map['entityType'] as String? ?? 'other',
      attachments: Attachment.listFromDynamic(map['attachments']),
      isArchived: map['isArchived'] as bool? ?? false,
      clientMutationId: map['clientMutationId'] as String? ?? '',
    );
  }
}
