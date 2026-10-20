import 'package:buildtrack_app/core/utils/number_parser.dart';
import 'package:buildtrack_app/core/utils/thousands_separator_input_formatter.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_item.dart';

/// One editable receipt row (feature 005). Amount and quantity are kept as the
/// text the user typed so formatting and partial input survive rebuilds.
class ExpenseItemDraft {
  ExpenseItemDraft({
    String? id,
    this.name = '',
    this.amountText = '',
    this.quantityText = '',
    this.note = '',
    this.needsReview = false,
  }) : id = id ?? ExpenseItem.newId();

  factory ExpenseItemDraft.fromItem(ExpenseItem item) {
    return ExpenseItemDraft(
      id: item.id == 'legacy' ? null : item.id,
      name: item.name,
      amountText: formatNumber(item.amount),
      quantityText: item.quantity == null ? '' : formatNumber(item.quantity!),
      note: item.note,
    );
  }

  final String id;
  final String name;
  final String amountText;
  final String quantityText;
  final String note;

  /// Set by the AI for rows it was unsure about; cleared once edited.
  final bool needsReview;

  double? get amount => NumberParser.parseDouble(amountText);
  double? get quantity => NumberParser.parseDouble(quantityText);
  bool get isBlank =>
      name.trim().isEmpty &&
      amountText.trim().isEmpty &&
      quantityText.trim().isEmpty &&
      note.trim().isEmpty;
  bool get isValid => name.trim().isNotEmpty && (amount ?? 0) > 0;

  /// The wire shape of data-model.md §2.
  Map<String, dynamic> toItemMap() => {
    'id': id,
    'name': name.trim(),
    'amount': amount ?? 0,
    'quantity': quantity,
    'note': note.trim(),
  };

  ExpenseItemDraft copyWith({
    String? id,
    String? name,
    String? amountText,
    String? quantityText,
    String? note,
    bool? needsReview,
  }) {
    return ExpenseItemDraft(
      id: id ?? this.id,
      name: name ?? this.name,
      amountText: amountText ?? this.amountText,
      quantityText: quantityText ?? this.quantityText,
      note: note ?? this.note,
      needsReview: needsReview ?? this.needsReview,
    );
  }

  static String formatNumber(double value) =>
      ThousandsSeparatorInputFormatter.formatInitial(value.toStringAsFixed(2));
}
