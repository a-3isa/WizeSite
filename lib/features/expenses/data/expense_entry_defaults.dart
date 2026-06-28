import 'package:buildtrack_app/core/constants/accounting_categories.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Remembers the last category / payment method / payment status the user
/// chose when adding an expense, so the next new expense form pre-fills with
/// them. Session-scoped (resets on app restart).
class ExpenseEntryDefaults {
  const ExpenseEntryDefaults({
    this.category = AccountingCategories.materials,
    this.paymentMethod = 'cash',
    this.paymentStatus = PaymentStatuses.unpaid,
  });

  final String category;
  final String paymentMethod;
  final String paymentStatus;
}

final expenseEntryDefaultsProvider = StateProvider<ExpenseEntryDefaults>(
  (ref) => const ExpenseEntryDefaults(),
);
