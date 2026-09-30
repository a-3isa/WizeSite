import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/reports/services/report_export_data_builder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExpenseRepository implements ExpenseRepository {
  _FakeExpenseRepository(this.pages);

  final List<FirestorePage<Expense>> pages;
  final List<
    ({String projectId, DateTime? startDate, DateTime? endDate, int pageSize})
  >
  calls = [];
  int _index = 0;

  @override
  Future<MutationResult> archiveExpense(String expenseId) async {
    return const MutationResult();
  }

  @override
  Future<MutationResult> createExpense({
    required String workspaceId,
    required String userId,
    required String projectId,
    String? projectName,
    required String category,
    required double amount,
    String? currency,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    double? projectTotalExpensesBefore,
    List<Attachment>? attachments,
  }) async {
    return const MutationResult();
  }

  @override
  Future<FirestorePage<Expense>> fetchExpensesPage(
    String workspaceId, {
    required String projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? category,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    Object? cursor,
    int pageSize = 20,
  }) async {
    calls.add((
      projectId: projectId,
      startDate: startDate,
      endDate: endDate,
      pageSize: pageSize,
    ));
    final page = pages[_index];
    if (_index < pages.length - 1) {
      _index += 1;
    }
    return page;
  }

  @override
  Future<Expense?> getExpense(String expenseId) async => null;

  @override
  Future<void> updateExpense({
    required String expenseId,
    required String category,
    required double amount,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    List<Attachment>? attachments,
  }) async {}

  @override
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId) {
    return const Stream<List<Expense>>.empty();
  }
}

class _FakePaymentRepository implements PaymentRepository {
  _FakePaymentRepository(this.pages);

  final List<FirestorePage<PaymentRecord>> pages;
  final List<
    ({String? projectId, DateTime? startDate, DateTime? endDate, int pageSize})
  >
  calls = [];
  int _index = 0;

  @override
  Future<MutationResult> archivePayment(String paymentId) async {
    return const MutationResult();
  }

  @override
  Future<MutationResult> createPayment({
    required String workspaceId,
    required String userId,
    required String projectId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? paymentStatus,
    double? paidAmount,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    double? projectTotalPaymentsBefore,
    List<Attachment>? attachments,
  }) async {
    return const MutationResult();
  }

  @override
  Future<FirestorePage<PaymentRecord>> fetchPaymentsPage(
    String workspaceId, {
    String? projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    Object? cursor,
    int pageSize = 20,
  }) async {
    calls.add((
      projectId: projectId,
      startDate: startDate,
      endDate: endDate,
      pageSize: pageSize,
    ));
    final page = pages[_index];
    if (_index < pages.length - 1) {
      _index += 1;
    }
    return page;
  }

  @override
  Future<PaymentRecord?> getPayment(String paymentId) async => null;

  @override
  Future<void> updatePayment({
    required String paymentId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? paymentStatus,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    List<Attachment>? attachments,
  }) async {}

  @override
  Stream<List<PaymentRecord>> watchPayments(
    String workspaceId, {
    String? projectId,
  }) {
    return const Stream<List<PaymentRecord>>.empty();
  }
}

Expense _expense({
  required String id,
  required String projectId,
  required DateTime date,
  required double amount,
  String entityId = 'supplier_1',
  String entityName = 'Supplier A',
}) {
  return Expense(
    id: id,
    workspaceId: 'workspace_1',
    projectId: projectId,
    projectName: projectId,
    category: 'materials',
    amount: amount,
    currency: 'EGP',
    date: date,
    notes: '',
    purpose: '',
    description: '',
    supplierName: entityName,
    entityId: entityId,
    entityName: entityName,
    entityType: 'supplier',
    paymentMethod: 'cash',
    paymentStatus: 'paid',
    inputMethod: 'manual',
    transcript: '',
    source: '',
    storagePath: '',
    attachments: const [],
    isArchived: false,
  );
}

PaymentRecord _payment({
  required String id,
  required String projectId,
  required DateTime date,
  required double amount,
  String entityId = 'supplier_1',
  String entityName = 'Supplier A',
  String paymentStatus = 'paid',
}) {
  return PaymentRecord(
    id: id,
    workspaceId: 'workspace_1',
    projectId: projectId,
    amount: amount,
    date: date,
    paymentMethod: 'bank',
    paymentStatus: paymentStatus,
    notes: '',
    entityId: entityId,
    entityName: entityName,
    entityType: 'supplier',
    attachments: const [],
    isArchived: false,
  );
}

Future<DocumentSnapshot<Map<String, dynamic>>> _cursor(String id) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('cursors').doc(id).set({'id': id});
  return firestore.collection('cursors').doc(id).get();
}

void main() {
  test(
    'builds scoped report data from project/date-bounded rows only',
    () async {
      final expenseRepository = _FakeExpenseRepository([
        FirestorePage<Expense>(
          items: [
            _expense(
              id: 'expense_1',
              projectId: 'project_1',
              date: DateTime.utc(2026, 6, 10),
              amount: 100,
            ),
            _expense(
              id: 'expense_2',
              projectId: 'project_2',
              date: DateTime.utc(2026, 6, 10),
              amount: 200,
              entityId: 'supplier_2',
              entityName: 'Other Project Supplier',
            ),
            _expense(
              id: 'expense_3',
              projectId: 'project_1',
              date: DateTime.utc(2026, 5, 31),
              amount: 300,
              entityId: 'supplier_3',
              entityName: 'Old Supplier',
            ),
          ],
          hasMore: false,
        ),
      ]);
      final paymentRepository = _FakePaymentRepository([
        FirestorePage<PaymentRecord>(
          items: [
            _payment(
              id: 'payment_1',
              projectId: 'project_1',
              date: DateTime.utc(2026, 6, 11),
              amount: 400,
            ),
            _payment(
              id: 'payment_2',
              projectId: 'project_2',
              date: DateTime.utc(2026, 6, 11),
              amount: 500,
              entityId: 'supplier_2',
              entityName: 'Other Project Supplier',
            ),
            _payment(
              id: 'payment_3',
              projectId: 'project_1',
              date: DateTime.utc(2026, 5, 30),
              amount: 600,
              entityId: 'supplier_3',
              entityName: 'Old Supplier',
            ),
          ],
          hasMore: false,
        ),
      ]);

      final result =
          await ReportExportDataBuilder(
            expenseRepository: expenseRepository,
            paymentRepository: paymentRepository,
          ).build(
            workspaceId: 'workspace_1',
            projectId: 'project_1',
            startDate: DateTime.utc(2026, 6, 1),
            endDate: DateTime.utc(2026, 6, 30, 23, 59, 59),
            includeExpenses: true,
            includePayments: true,
            includeEntities: true,
            includeDaily: true,
            includeWeekly: false,
          );

      expect(result.expenses.map((item) => item.id), ['expense_1']);
      expect(result.payments.map((item) => item.id), ['payment_1']);
      expect(result.entitySummaries, hasLength(1));
      expect(result.entitySummaries.single.entityName, 'Supplier A');
      expect(result.entitySummaries.single.totalExpenses, 100);
      expect(result.entitySummaries.single.totalPayments, 400);
      expect(result.entitySummaries.single.transactionCount, 2);
      expect(expenseRepository.calls.single.projectId, 'project_1');
      expect(paymentRepository.calls.single.projectId, 'project_1');
    },
  );

  test('entity payment totals use cash collected not gross amount', () async {
    final expenseRepository = _FakeExpenseRepository([
      const FirestorePage<Expense>(items: [], hasMore: false),
    ]);
    final paymentRepository = _FakePaymentRepository([
      FirestorePage<PaymentRecord>(
        items: [
          _payment(
            id: 'payment_unpaid',
            projectId: 'project_1',
            date: DateTime.utc(2026, 6, 11),
            amount: 10000,
            paymentStatus: 'unpaid',
          ),
        ],
        hasMore: false,
      ),
    ]);

    final result = await ReportExportDataBuilder(
      expenseRepository: expenseRepository,
      paymentRepository: paymentRepository,
    ).build(
      workspaceId: 'workspace_1',
      projectId: 'project_1',
      startDate: DateTime.utc(2026, 6, 1),
      endDate: DateTime.utc(2026, 6, 30, 23, 59, 59),
      includeExpenses: false,
      includePayments: true,
      includeEntities: true,
      includeDaily: false,
      includeWeekly: false,
    );

    expect(result.entitySummaries.single.totalPayments, 0);
  });

  test('continues paging until all report rows are loaded', () async {
    final expenseRepository = _FakeExpenseRepository([
      FirestorePage<Expense>(
        items: List.generate(
          500,
          (index) => _expense(
            id: 'expense_$index',
            projectId: 'project_1',
            date: DateTime.utc(2026, 6, 10),
            amount: 1,
          ),
        ),
        hasMore: true,
        nextCursor: await _cursor('expense_page_1'),
      ),
      FirestorePage<Expense>(
        items: List.generate(
          25,
          (index) => _expense(
            id: 'expense_tail_$index',
            projectId: 'project_1',
            date: DateTime.utc(2026, 6, 11),
            amount: 1,
          ),
        ),
        hasMore: false,
      ),
    ]);
    final paymentRepository = _FakePaymentRepository([
      const FirestorePage<PaymentRecord>(items: [], hasMore: false),
    ]);

    final progress = <ReportExportProgress>[];
    final result =
        await ReportExportDataBuilder(
          expenseRepository: expenseRepository,
          paymentRepository: paymentRepository,
        ).build(
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          startDate: DateTime.utc(2026, 6, 1),
          endDate: DateTime.utc(2026, 6, 30, 23, 59, 59),
          includeExpenses: true,
          includePayments: false,
          includeEntities: false,
          includeDaily: false,
          includeWeekly: false,
          onProgress: progress.add,
        );

    expect(result.expenses, hasLength(525));
    expect(expenseRepository.calls, hasLength(2));
    expect(expenseRepository.calls.first.pageSize, 500);
    expect(
      progress
          .where((item) => item.stage == ReportExportStage.expenses)
          .map((item) => item.loadedRecords),
      [500, 525],
    );
    expect(progress.last.stage, ReportExportStage.complete);
  });

  test('cooperative cancellation stops before the next export page', () async {
    final expenseRepository = _FakeExpenseRepository([
      FirestorePage<Expense>(
        items: [
          _expense(
            id: 'expense_1',
            projectId: 'project_1',
            date: DateTime.utc(2026, 6, 10),
            amount: 1,
          ),
        ],
        hasMore: true,
        nextCursor: await _cursor('expense_page_1'),
      ),
      const FirestorePage<Expense>(items: [], hasMore: false),
    ]);
    final paymentRepository = _FakePaymentRepository([
      const FirestorePage<PaymentRecord>(items: [], hasMore: false),
    ]);
    var cancelled = false;

    await expectLater(
      ReportExportDataBuilder(
        expenseRepository: expenseRepository,
        paymentRepository: paymentRepository,
      ).build(
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        startDate: DateTime.utc(2026, 6, 1),
        endDate: DateTime.utc(2026, 6, 30, 23, 59, 59),
        includeExpenses: true,
        includePayments: true,
        includeEntities: false,
        includeDaily: false,
        includeWeekly: false,
        isCancelled: () => cancelled,
        onProgress: (_) => cancelled = true,
      ),
      throwsA(isA<ReportExportCancelled>()),
    );

    expect(expenseRepository.calls, hasLength(1));
    expect(paymentRepository.calls, isEmpty);
  });
}
