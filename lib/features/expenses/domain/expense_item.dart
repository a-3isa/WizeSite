import 'dart:convert';
import 'dart:math';

/// One line of a receipt (feature 005, data-model.md §2). Stored in order in
/// the expense's `items` list; the expense amount is their sum.
class ExpenseItem {
  const ExpenseItem({
    required this.id,
    required this.name,
    required this.amount,
    this.quantity,
    this.note = '',
  });

  final String id;
  final String name;
  final double amount;

  /// Informational only: never multiplies [amount] (the line total).
  final double? quantity;
  final String note;

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  /// Throws [FormatException] when the amount is missing or not a number;
  /// [listFromDynamic] skips such elements.
  factory ExpenseItem.fromMap(Map<String, dynamic> map) {
    final amount = _number(map['amount']);
    if (amount == null) {
      throw const FormatException('Expense item amount is missing');
    }
    return ExpenseItem(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? ''}',
      amount: amount,
      quantity: _number(map['quantity']),
      note: '${map['note'] ?? ''}',
    );
  }

  /// Accepts a list or JSON text (the local replica stores JSON); bad
  /// elements are skipped and nothing here ever throws.
  static List<ExpenseItem> listFromDynamic(Object? raw) {
    var value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return const <ExpenseItem>[];
      }
    }
    if (value is! Iterable) {
      return const <ExpenseItem>[];
    }
    final items = <ExpenseItem>[];
    for (final element in value) {
      if (element is! Map) continue;
      try {
        items.add(ExpenseItem.fromMap(Map<String, dynamic>.from(element)));
      } on FormatException {
        continue;
      }
    }
    return List.unmodifiable(items);
  }

  static const _idAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static final _random = Random.secure();

  /// 10 random `[a-z0-9]` characters, accepted by the server's id check.
  static String newId() => List.generate(
    10,
    (_) => _idAlphabet[_random.nextInt(_idAlphabet.length)],
  ).join();

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'amount': amount,
    'quantity': quantity,
    'note': note,
  };

  ExpenseItem copyWith({
    String? id,
    String? name,
    double? amount,
    double? quantity,
    String? note,
  }) {
    return ExpenseItem(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      quantity: quantity ?? this.quantity,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExpenseItem &&
      other.id == id &&
      other.name == name &&
      other.amount == amount &&
      other.quantity == quantity &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, name, amount, quantity, note);

  @override
  String toString() => 'ExpenseItem($id, $name, $amount)';
}
