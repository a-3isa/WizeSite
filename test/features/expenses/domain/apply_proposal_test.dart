import 'package:buildtrack_app/features/expenses/domain/expense_item_draft.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_proposal.dart';
import 'package:flutter_test/flutter_test.dart';

ExpenseProposal _proposal({
  String? title = 'سباكه شهر 10',
  List<ProposalItem> items = const [
    ProposalItem(name: 'حنفية', amount: 100),
    ProposalItem(name: 'جلبه', amount: 50),
  ],
  String? projectId = 'p_villa',
  String? category = 'materials',
  String? entityId = 'e_hassan',
  String? entityName = 'ورشة حسن',
  String? date = '2026-10-18',
  String? paymentStatus = 'paid',
}) {
  return ExpenseProposal(
    title: title,
    items: items,
    projectId: projectId,
    projectName: projectId == null ? null : 'فيلا',
    category: category,
    entityId: entityId,
    entityName: entityName,
    date: date,
    paymentStatus: paymentStatus,
    currency: 'EGP',
  );
}

const _untouched = ExpenseFormSnapshot(
  title: '',
  projectId: null,
  category: null,
  entityId: null,
  entityName: '',
  date: null,
  paymentStatus: 'unpaid',
  items: [],
);

void main() {
  test('fromMap is tolerant of missing keys and old servers', () {
    final proposal = ExpenseProposal.fromMap({
      'title': 'سباكه',
      'items': [
        {'name': 'حنفية', 'amount': 100, 'needsReview': false},
        {'name': null, 'amount': '50', 'quantity': 2, 'needsReview': true},
        'junk',
      ],
      'totalMismatch': true,
    });
    expect(proposal.items, hasLength(2));
    expect(proposal.items[1].amount, 50);
    expect(proposal.items[1].quantity, 2);
    expect(proposal.items[1].needsReview, isTrue);
    expect(proposal.totalMismatch, isTrue);
    expect(proposal.multipleReceiptsSuspected, isFalse);
    expect(proposal.currency, 'EGP');
    expect(ExpenseProposal.fromMap(const {}).items, isEmpty);
  });

  test('proposedTitle falls back to the first item name', () {
    expect(_proposal().proposedTitle, 'سباكه شهر 10');
    expect(
      _proposal(
        title: null,
        items: const [ProposalItem(name: 'رمل', amount: 2000)],
      ).proposedTitle,
      'رمل',
    );
    expect(_proposal(title: ' ', items: const []).proposedTitle, isNull);
  });

  test('toDrafts gives one row per item, or one flagged row when empty', () {
    final drafts = _proposal().toDrafts();
    expect(drafts.map((d) => d.name), ['حنفية', 'جلبه']);
    expect(drafts.first.amountText, '100.00');
    expect(drafts.map((d) => d.id).toSet(), hasLength(2));

    final empty = _proposal(items: const []).toDrafts();
    expect(empty, hasLength(1));
    expect(empty.single.needsReview, isTrue);
    expect(empty.single.isBlank, isTrue);
  });

  test('an untouched form takes every proposed field', () {
    final next = applyProposal(_untouched, _proposal());
    expect(next.title, 'سباكه شهر 10');
    expect(next.projectId, 'p_villa');
    expect(next.category, 'materials');
    expect(next.entityId, 'e_hassan');
    expect(next.entityName, 'ورشة حسن');
    expect(next.date, DateTime(2026, 10, 18));
    expect(next.paymentStatus, 'paid');
    expect(next.items.map((d) => d.name), ['حنفية', 'جلبه']);
  });

  test('user-edited fields are kept while the others are filled', () {
    final form = _untouched.copyWith(
      projectId: 'p_mine',
      projectEdited: true,
      title: 'عنواني',
      titleEdited: true,
    );
    final next = applyProposal(form, _proposal());
    expect(next.projectId, 'p_mine');
    expect(next.title, 'عنواني');
    expect(next.entityName, 'ورشة حسن');
    expect(next.paymentStatus, 'paid');
  });

  test('typed item rows are kept and proposal items come after them', () {
    final form = _untouched.copyWith(
      items: [ExpenseItemDraft(name: 'سلك', amountText: '30')],
      itemsHaveUserEdits: true,
    );
    final next = applyProposal(form, _proposal());
    expect(next.items.map((d) => d.name), ['سلك', 'حنفية', 'جلبه']);
  });

  test('a single untouched empty row is replaced, not appended to', () {
    final form = _untouched.copyWith(items: [ExpenseItemDraft()]);
    final next = applyProposal(form, _proposal());
    expect(next.items.map((d) => d.name), ['حنفية', 'جلبه']);
  });

  test('null proposal fields change nothing', () {
    final form = _untouched.copyWith(paymentStatus: 'partial');
    final next = applyProposal(
      form,
      _proposal(
        title: null,
        items: const [],
        projectId: null,
        category: null,
        entityId: null,
        entityName: null,
        date: null,
        paymentStatus: null,
      ),
    );
    expect(next.title, '');
    expect(next.projectId, isNull);
    expect(next.category, isNull);
    expect(next.entityName, '');
    expect(next.date, isNull);
    expect(next.paymentStatus, 'partial');
    expect(next.items, isEmpty);
  });
}
