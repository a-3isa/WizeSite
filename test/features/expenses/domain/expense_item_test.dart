import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_item.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _expenseMap(Object? items, {String description = ''}) {
  return {
    'workspaceId': 'workspace_1',
    'projectId': 'project_1',
    'category': 'materials',
    'amount': 240,
    'date': '2026-10-19T00:00:00.000Z',
    'description': description,
    'items': ?items,
  };
}

void main() {
  test('ExpenseItem round-trips through toMap/fromMap', () {
    const item = ExpenseItem(
      id: 'item_a1',
      name: 'حنفية',
      amount: 100,
      quantity: 2,
      note: 'كبيرة',
    );
    expect(ExpenseItem.fromMap(item.toMap()), item);
    expect(item.toMap(), {
      'id': 'item_a1',
      'name': 'حنفية',
      'amount': 100.0,
      'quantity': 2.0,
      'note': 'كبيرة',
    });
  });

  test('fromMap accepts numbers as strings and defaults optional fields', () {
    final item = ExpenseItem.fromMap({
      'id': 'x1',
      'name': 'جلبه',
      'amount': '50',
    });
    expect(item.amount, 50);
    expect(item.quantity, isNull);
    expect(item.note, '');
  });

  test('Expense.fromMap reads items from a list or JSON text, in order', () {
    final fromList = Expense.fromMap(
      'e1',
      _expenseMap([
        {'id': 'a', 'name': 'حنفية', 'amount': 100},
        {'id': 'b', 'name': 'جلبه', 'amount': 50},
        {'id': 'c', 'name': 'ماسورة', 'amount': 90},
      ]),
    );
    expect(fromList.items.map((i) => i.name), ['حنفية', 'جلبه', 'ماسورة']);
    expect(fromList.itemCount, 3);

    final fromJson = Expense.fromMap(
      'e2',
      _expenseMap('[{"id":"a","name":"رمل","amount":2000}]'),
    );
    expect(fromJson.items.single.name, 'رمل');
  });

  test('missing, non-list and malformed items never throw', () {
    expect(Expense.fromMap('e1', _expenseMap(null)).items, isEmpty);
    expect(Expense.fromMap('e2', _expenseMap('x')).items, isEmpty);
    expect(Expense.fromMap('e3', _expenseMap(42)).items, isEmpty);
    final mixed = Expense.fromMap(
      'e4',
      _expenseMap([
        'not a map',
        {'id': 'a', 'name': 'حنفية', 'amount': 100},
        {'id': 'b', 'name': 'bad', 'amount': 'abc'},
      ]),
    );
    expect(mixed.items.map((i) => i.id), ['a']);
  });

  test('legacy expense (no items) has one effective item from its amount', () {
    final legacy = Expense.fromMap(
      'old',
      _expenseMap(null, description: '  أسمنت '),
    );
    expect(legacy.items, isEmpty);
    expect(legacy.effectiveItems, [
      const ExpenseItem(id: 'legacy', name: 'أسمنت', amount: 240),
    ]);
    expect(legacy.itemCount, 1);
  });

  test('title is the description', () {
    final expense = Expense.fromMap(
      'e1',
      _expenseMap(const [], description: 'سباكه شهر 10'),
    );
    expect(expense.title, 'سباكه شهر 10');
  });

  test('newId gives distinct ids the server accepts', () {
    final ids = List.generate(50, (_) => ExpenseItem.newId()).toSet();
    expect(ids, hasLength(50));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{6,36}$')));
    }
  });
}
