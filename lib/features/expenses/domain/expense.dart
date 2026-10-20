import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_item.dart';

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
    this.purpose = '',
    this.description = '',
    required this.supplierName,
    required this.paymentMethod,
    this.paymentStatus = PaymentStatuses.unpaid,
    this.entityId,
    this.entityName = '',
    this.entityType = '',
    required this.inputMethod,
    required this.transcript,
    required this.source,
    required this.storagePath,
    required this.isArchived,
    required this.attachments,
    this.items = const [],
    this.clientMutationId = '',
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
  final String purpose;
  final String description;
  final String supplierName;
  final String paymentMethod;
  final String paymentStatus;
  final String? entityId;
  final String entityName;
  final String entityType;
  final String inputMethod;
  final String transcript;
  final String source;
  final String storagePath;
  final List<Attachment> attachments;

  /// Receipt line items in order (feature 005). Empty for expenses recorded
  /// before items existed; read those through [effectiveItems].
  final List<ExpenseItem> items;
  final bool isArchived;
  final String clientMutationId;

  /// The expense title is stored in [description] (research R4).
  String get title => description;

  /// [items], or for a legacy expense one item carrying its whole amount.
  List<ExpenseItem> get effectiveItems => items.isNotEmpty
      ? items
      : [ExpenseItem(id: 'legacy', name: description.trim(), amount: amount)];

  int get itemCount => effectiveItems.length;

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
      purpose: map['purpose'] as String? ?? '',
      description:
          map['description'] as String? ?? map['notes'] as String? ?? '',
      supplierName: map['supplierName'] as String? ?? '',
      entityId: map['entityId'] as String?,
      entityName:
          map['entityName'] as String? ?? map['supplierName'] as String? ?? '',
      entityType: map['entityType'] as String? ?? 'supplier',
      paymentMethod: map['paymentMethod'] as String? ?? '',
      paymentStatus: map['paymentStatus'] as String? ?? PaymentStatuses.unpaid,
      inputMethod: map['inputMethod'] as String? ?? 'manual',
      transcript: map['transcript'] as String? ?? '',
      source: map['source'] as String? ?? '',
      storagePath: map['storagePath'] as String? ?? '',
      attachments: Attachment.listFromDynamic(map['attachments']),
      items: ExpenseItem.listFromDynamic(map['items']),
      isArchived: map['isArchived'] as bool? ?? false,
      clientMutationId: map['clientMutationId'] as String? ?? '',
    );
  }
}
