import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/features/expenses/presentation/widgets/expense_items_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _l10n = AppLocalizations(const Locale('en'));

Widget _host(
  ExpenseItemsEditorController controller, {
  ValueChanged<List<ExpenseItemDraft>>? onChanged,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ExpenseItemsEditor(
            controller: controller,
            currency: 'EGP',
            onChanged: onChanged,
          ),
        ],
      ),
    ),
  );
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

void main() {
  testWidgets('starts with one empty row', (tester) async {
    final controller = ExpenseItemsEditorController();
    await tester.pumpWidget(_host(controller));
    expect(find.byKey(const Key('qa_item_name_0')), findsOneWidget);
    expect(find.byKey(const Key('qa_item_name_1')), findsNothing);
    expect(controller.isPristine, isTrue);
  });

  testWidgets('add item appends a row and the total follows typing', (
    tester,
  ) async {
    final controller = ExpenseItemsEditorController();
    await tester.pumpWidget(_host(controller));
    await _type(tester, 'qa_item_name_0', 'حنفية');
    await _type(tester, 'qa_item_amount_0', '100');
    await tester.tap(find.byKey(const Key('qa_items_add')));
    await tester.pump();
    await _type(tester, 'qa_item_name_1', 'جلبه');
    await _type(tester, 'qa_item_amount_1', '50');
    await tester.tap(find.byKey(const Key('qa_items_add')));
    await tester.pump();
    await _type(tester, 'qa_item_name_2', 'ماسورة');
    await _type(tester, 'qa_item_amount_2', '90');

    expect(controller.total, 240);
    expect(find.text('240.00 EGP'), findsOneWidget);
    expect(controller.toItemMaps().map((m) => m['name']), [
      'حنفية',
      'جلبه',
      'ماسورة',
    ]);
    expect(controller.hasUserEdits, isTrue);
  });

  testWidgets('delete removes a row but never the last one', (tester) async {
    final controller = ExpenseItemsEditorController([
      ExpenseItemDraft(name: 'a', amountText: '1'),
      ExpenseItemDraft(name: 'b', amountText: '2'),
    ]);
    await tester.pumpWidget(_host(controller));
    await tester.tap(find.byKey(const Key('qa_item_remove_0')));
    await tester.pump();
    expect(controller.items.single.name, 'b');

    await tester.tap(find.byKey(const Key('qa_item_remove_0')));
    await tester.pump();
    expect(controller.length, 1, reason: 'last row kept');
    expect(find.text(_l10n.t('cannotRemoveLastItem')), findsOneWidget);
  });

  testWidgets('validate marks rows without a name or a positive amount', (
    tester,
  ) async {
    final controller = ExpenseItemsEditorController([
      ExpenseItemDraft(name: 'ok', amountText: '10'),
      ExpenseItemDraft(name: '', amountText: '5'),
      ExpenseItemDraft(name: 'zero', amountText: '0'),
    ]);
    await tester.pumpWidget(_host(controller));
    expect(controller.validate(), isFalse);
    await tester.pump();
    expect(controller.invalidIds, hasLength(2));
    expect(find.text(_l10n.t('itemNameRequired')), findsOneWidget);
    expect(find.text(_l10n.t('itemAmountRequired')), findsOneWidget);

    await _type(tester, 'qa_item_name_1', 'سلك');
    await _type(tester, 'qa_item_amount_2', '3');
    expect(controller.validate(), isTrue);
  });

  testWidgets('a needs-review row is flagged until edited', (tester) async {
    final controller = ExpenseItemsEditorController([
      ExpenseItemDraft(name: 'لمبة', amountText: '20', needsReview: true),
    ]);
    await tester.pumpWidget(_host(controller));
    expect(find.byKey(const Key('qa_item_review_0')), findsOneWidget);
    expect(controller.validate(), isFalse, reason: 'flagged rows block save');

    await _type(tester, 'qa_item_amount_0', '25');
    expect(find.byKey(const Key('qa_item_review_0')), findsNothing);
    expect(controller.validate(), isTrue);
  });

  testWidgets('reorder changes the order reported to onChanged', (
    tester,
  ) async {
    List<ExpenseItemDraft>? reported;
    final controller = ExpenseItemsEditorController([
      ExpenseItemDraft(name: 'a', amountText: '1'),
      ExpenseItemDraft(name: 'b', amountText: '2'),
      ExpenseItemDraft(name: 'c', amountText: '3'),
    ]);
    await tester.pumpWidget(_host(controller, onChanged: (v) => reported = v));
    expect(find.byType(ReorderableListView), findsOneWidget);

    controller.reorder(0, 2);
    await tester.pump();
    expect(reported!.map((r) => r.name), ['b', 'c', 'a']);
    expect(controller.hasUserEdits, isTrue);
  });

  testWidgets('quantity and note sit behind the expand control', (
    tester,
  ) async {
    final controller = ExpenseItemsEditorController();
    await tester.pumpWidget(_host(controller));
    expect(find.byKey(const Key('qa_item_quantity_0')), findsNothing);
    await tester.tap(find.byKey(const Key('qa_item_expand_0')));
    await tester.pump();
    await _type(tester, 'qa_item_quantity_0', '2');
    await _type(tester, 'qa_item_note_0', 'كبيرة');
    expect(controller.items.single.quantity, 2);
    expect(controller.toItemMaps().single['note'], 'كبيرة');
  });

  testWidgets('100 rows render without overflow and adding stops there', (
    tester,
  ) async {
    final controller = ExpenseItemsEditorController([
      for (var i = 0; i < maxExpenseItems; i++)
        ExpenseItemDraft(name: 'بند $i', amountText: '1'),
    ]);
    await tester.pumpWidget(_host(controller));
    expect(tester.takeException(), isNull);
    expect(controller.total, 100);
    await tester.scrollUntilVisible(
      find.byKey(const Key('qa_items_add')),
      2000,
      scrollable: find.byType(Scrollable).first,
    );
    final add = tester.widget<TextButton>(
      find.ancestor(
        of: find.text(_l10n.t('addItem')),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    );
    expect(add.onPressed, isNull);
  });

  test('appendItems replaces a pristine row and keeps typed rows', () {
    final pristine = ExpenseItemsEditorController();
    pristine.appendItems([ExpenseItemDraft(name: 'x', amountText: '1')]);
    expect(pristine.items.map((r) => r.name), ['x']);

    final typed = ExpenseItemsEditorController([
      ExpenseItemDraft(name: 'mine', amountText: '5'),
    ]);
    typed.appendItems([ExpenseItemDraft(name: 'ai', amountText: '7')]);
    expect(typed.items.map((r) => r.name), ['mine', 'ai']);
    expect(typed.total, 12);
  });

  test('setFirstItemAmount only applies with a single row', () {
    final single = ExpenseItemsEditorController();
    single.setFirstItemAmount(600);
    expect(single.items.single.amountText, '600.00');

    final two = ExpenseItemsEditorController([
      ExpenseItemDraft(name: 'a', amountText: '1'),
      ExpenseItemDraft(name: 'b', amountText: '2'),
    ]);
    two.setFirstItemAmount(600);
    expect(two.items.first.amountText, '1');
  });
}
