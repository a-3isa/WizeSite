import 'package:buildtrack_app/features/expenses/domain/expense_item.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_item_draft.dart';

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

String? _text(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

/// One line of an AI proposal (data-model.md §6).
class ProposalItem {
  const ProposalItem({
    this.name,
    this.amount,
    this.quantity,
    this.needsReview = false,
  });

  factory ProposalItem.fromMap(Map<String, dynamic> map) {
    return ProposalItem(
      name: _text(map['name']),
      amount: _number(map['amount']),
      quantity: _number(map['quantity']),
      needsReview: map['needsReview'] == true,
    );
  }

  final String? name;
  final double? amount;
  final double? quantity;
  final bool needsReview;
}

/// The AI's understanding of a recording or pasted text (feature 005):
/// transient, shown for review, never stored.
class ExpenseProposal {
  const ExpenseProposal({
    this.title,
    this.items = const [],
    this.projectId,
    this.projectName,
    this.category,
    this.entityId,
    this.entityName,
    this.date,
    this.paymentStatus,
    this.currency = 'EGP',
    this.statedTotal,
    this.totalMismatch = false,
    this.multipleReceiptsSuspected = false,
  });

  /// Tolerant of missing keys, so an older or partial response never throws.
  factory ExpenseProposal.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'];
    return ExpenseProposal(
      title: _text(map['title']),
      items: [
        if (rawItems is List)
          for (final item in rawItems)
            if (item is Map)
              ProposalItem.fromMap(Map<String, dynamic>.from(item)),
      ],
      projectId: _text(map['projectId']),
      projectName: _text(map['projectName']),
      category: _text(map['category']),
      entityId: _text(map['entityId']),
      entityName: _text(map['entityName']),
      date: _text(map['date']),
      paymentStatus: _text(map['paymentStatus']),
      currency: _text(map['currency']) ?? 'EGP',
      statedTotal: _number(map['statedTotal']),
      totalMismatch: map['totalMismatch'] == true,
      multipleReceiptsSuspected: map['multipleReceiptsSuspected'] == true,
    );
  }

  final String? title;
  final List<ProposalItem> items;
  final String? projectId;
  final String? projectName;
  final String? category;
  final String? entityId;
  final String? entityName;

  /// `YYYY-MM-DD`.
  final String? date;
  final String? paymentStatus;
  final String currency;
  final double? statedTotal;
  final bool totalMismatch;
  final bool multipleReceiptsSuspected;

  /// The title, else the first named item (spec Story 2 scenario 4).
  String? get proposedTitle {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    for (final item in items) {
      final name = item.name?.trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  DateTime? get parsedDate {
    final value = date;
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  double get itemsTotal {
    var piastres = 0;
    for (final item in items) {
      piastres += ((item.amount ?? 0) * 100).round();
    }
    return piastres / 100;
  }

  /// Editor rows for the items; a proposal with no items gives one empty
  /// flagged row, because the editor never has zero rows.
  List<ExpenseItemDraft> toDrafts() {
    if (items.isEmpty) {
      return [ExpenseItemDraft(needsReview: true)];
    }
    return [
      for (final item in items)
        ExpenseItemDraft(
          id: ExpenseItem.newId(),
          name: item.name ?? '',
          amountText: item.amount == null
              ? ''
              : ExpenseItemDraft.formatNumber(item.amount!),
          quantityText: item.quantity == null
              ? ''
              : ExpenseItemDraft.formatNumber(item.quantity!),
          needsReview: item.needsReview,
        ),
    ];
  }
}

/// The add-expense form as [applyProposal] sees it: each field's value and
/// whether the user already set it by hand.
class ExpenseFormSnapshot {
  const ExpenseFormSnapshot({
    required this.title,
    required this.projectId,
    required this.category,
    required this.entityId,
    required this.entityName,
    required this.date,
    required this.paymentStatus,
    required this.items,
    this.titleEdited = false,
    this.projectEdited = false,
    this.categoryEdited = false,
    this.entityEdited = false,
    this.dateEdited = false,
    this.paymentStatusEdited = false,
    this.itemsHaveUserEdits = false,
  });

  final String title;
  final String? projectId;
  final String? category;
  final String? entityId;
  final String entityName;
  final DateTime? date;
  final String paymentStatus;
  final List<ExpenseItemDraft> items;
  final bool titleEdited;
  final bool projectEdited;
  final bool categoryEdited;
  final bool entityEdited;
  final bool dateEdited;
  final bool paymentStatusEdited;
  final bool itemsHaveUserEdits;

  ExpenseFormSnapshot copyWith({
    String? title,
    String? projectId,
    String? category,
    String? entityId,
    String? entityName,
    DateTime? date,
    String? paymentStatus,
    List<ExpenseItemDraft>? items,
    bool? titleEdited,
    bool? projectEdited,
    bool? categoryEdited,
    bool? entityEdited,
    bool? dateEdited,
    bool? paymentStatusEdited,
    bool? itemsHaveUserEdits,
  }) {
    return ExpenseFormSnapshot(
      title: title ?? this.title,
      projectId: projectId ?? this.projectId,
      category: category ?? this.category,
      entityId: entityId ?? this.entityId,
      entityName: entityName ?? this.entityName,
      date: date ?? this.date,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      items: items ?? this.items,
      titleEdited: titleEdited ?? this.titleEdited,
      projectEdited: projectEdited ?? this.projectEdited,
      categoryEdited: categoryEdited ?? this.categoryEdited,
      entityEdited: entityEdited ?? this.entityEdited,
      dateEdited: dateEdited ?? this.dateEdited,
      paymentStatusEdited: paymentStatusEdited ?? this.paymentStatusEdited,
      itemsHaveUserEdits: itemsHaveUserEdits ?? this.itemsHaveUserEdits,
    );
  }
}

/// Merges an AI proposal into the form (research R7, clarification Q3): a
/// field is filled only when the proposal mentions it and the user has not
/// set it by hand; proposal items are appended after rows the user typed,
/// and replace a single untouched empty row.
ExpenseFormSnapshot applyProposal(
  ExpenseFormSnapshot form,
  ExpenseProposal proposal,
) {
  final pristineItems =
      !form.itemsHaveUserEdits && form.items.every((row) => row.isBlank);
  final proposedTitle = proposal.proposedTitle;
  final proposedEntity = proposal.entityName;
  return form.copyWith(
    title: !form.titleEdited && proposedTitle != null ? proposedTitle : null,
    projectId: !form.projectEdited ? proposal.projectId : null,
    category: !form.categoryEdited ? proposal.category : null,
    entityId: !form.entityEdited && proposedEntity != null
        ? proposal.entityId ?? ''
        : null,
    entityName: !form.entityEdited ? proposedEntity : null,
    date: !form.dateEdited ? proposal.parsedDate : null,
    paymentStatus: !form.paymentStatusEdited ? proposal.paymentStatus : null,
    items: proposal.items.isEmpty
        ? null
        : [if (!pristineItems) ...form.items, ...proposal.toDrafts()],
  );
}
