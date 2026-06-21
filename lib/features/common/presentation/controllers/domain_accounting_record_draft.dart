class DomainAccountingRecordDraft {
  const DomainAccountingRecordDraft({
    required this.workspaceId,
    required this.projectId,
    required this.ownerIdField,
    required this.ownerNameField,
    required this.ownerId,
    required this.ownerName,
    required this.description,
    required this.amount,
    required this.date,
    required this.paymentMethod,
    required this.paymentStatus,
    this.paidAmount,
    required this.notes,
  });

  final String workspaceId;
  final String projectId;
  final String ownerIdField;
  final String ownerNameField;
  final String ownerId;
  final String ownerName;
  final String description;
  final double amount;
  final DateTime date;
  final String paymentMethod;
  final String paymentStatus;
  final double? paidAmount;
  final String notes;
}

class DomainAccountingValidationException implements Exception {
  const DomainAccountingValidationException(this.messageKey);

  final String messageKey;
}
