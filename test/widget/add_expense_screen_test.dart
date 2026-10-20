import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/accounting_categories.dart';
import 'package:buildtrack_app/core/constants/accounting_entity_types.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_item.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/add_expense_screen.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/features/expenses/data/expense_text_organizer.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_proposal.dart';
import 'package:buildtrack_app/features/voice_expense/data/voice_ai_disclosure_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExpenseRepository implements ExpenseRepository {
  _FakeExpenseRepository({this.stored});

  /// Returned by [getExpense] (edit mode).
  final Expense? stored;

  /// Named arguments of the last createExpense / updateExpense call.
  Map<String, Object?>? lastCreate;
  Map<String, Object?>? lastUpdate;

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
    List<Map<String, dynamic>>? items,
    String inputMethod = 'manual',
    String? transcript,
    String? source,
  }) async {
    lastCreate = {
      'projectId': projectId,
      'category': category,
      'amount': amount,
      'description': description,
      'items': items,
      'inputMethod': inputMethod,
      'transcript': transcript,
      'source': source,
      'entityName': entityName,
      'paymentStatus': paymentStatus,
    };
    return const MutationResult();
  }

  @override
  Future<RecordPage<Expense>> fetchExpensesPage(
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
    return const RecordPage(items: [], hasMore: false);
  }

  @override
  Future<Expense?> getExpense(String expenseId) async => stored;

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
    List<Map<String, dynamic>>? items,
  }) async {
    lastUpdate = {
      'expenseId': expenseId,
      'amount': amount,
      'description': description,
      'items': items,
    };
  }

  @override
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId) {
    return const Stream.empty();
  }
}

void main() {
  testWidgets(
    'AddExpenseScreen waits for category before showing detail fields',
    (tester) async {
      await tester.pumpWidget(_screen(locale: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Purpose'), findsNothing);
      expect(find.text('Description'), findsNothing);
      expect(find.text('Payment method'), findsNothing);
      expect(find.text('Payment status'), findsNothing);
      expect(find.text('Currency'), findsNothing);
    },
  );

  testWidgets('AddExpenseScreen localizes attachment controls in Arabic', (
    tester,
  ) async {
    const locale = Locale('ar');
    final l10n = AppLocalizations(locale);
    await tester.pumpWidget(_screen(locale: locale));

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa_add_expense_category')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(l10n.expenseCategoryLabel(AccountingCategories.materials)).last,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('qa_add_expense_pick_attachments')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text(l10n.t('attachments')), findsOneWidget);
    expect(find.text(l10n.t('selectAttachments')), findsOneWidget);
    expect(find.text('Attachments'), findsNothing);
    expect(find.text('Select attachments'), findsNothing);
  });

  testWidgets('empty amount shows what to do instead of saving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final l10n = AppLocalizations(const Locale('en'));
    await tester.pumpWidget(
      _screen(locale: const Locale('en'), projectId: 'project_1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa_add_expense_category')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(l10n.expenseCategoryLabel(AccountingCategories.materials)).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa_add_expense_save')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.t('selectProjectAndValidAmount')), findsOneWidget);
  });

  testWidgets('resource category shows saved resources and calculates amount', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final contractor = AppEntity(
      id: 'contractor_1',
      workspaceId: 'workspace_1',
      name: 'BuildCo',
      normalizedName: 'buildco',
      type: AccountingEntityTypes.contractor,
      createdAt: DateTime(2026),
      defaultRate: 250,
      rateUnit: 'day',
    );
    await tester.pumpWidget(
      _screen(
        locale: const Locale('en'),
        entityRepository: _FakeEntityRepository([contractor]),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa_add_expense_category')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .text(
            AppLocalizations(
              const Locale('en'),
            ).expenseCategoryLabel(AccountingCategories.contractor),
          )
          .last,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextField, 'Entity name (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('BuildCo'), findsOneWidget);

    await tester.tap(find.text('BuildCo'));
    await tester.pumpAndSettle();
    expect(find.text('250.00'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '3');
    await tester.pumpAndSettle();
    expect(find.text('750.00'), findsOneWidget);
  });

  testWidgets('worker category saves through worker entry repository', (
    tester,
  ) async {
    final worker = WorkerProfile(
      id: 'worker_1',
      workspaceId: 'workspace_1',
      name: 'Mina',
      phoneNumber: '0100',
      dailyWage: 120,
      billingType: 'daily',
      workerType: 'mason',
      notes: '',
      isArchived: false,
    );
    final entries = _FakeWorkerEntryRepository();
    await tester.pumpWidget(
      _screen(
        locale: const Locale('en'),
        projectId: 'project_1',
        workerRepository: _FakeWorkerRepository([worker]),
        workerEntryRepository: entries,
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa_add_expense_category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Worker').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownMenu<String>, 'Worker Name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mina').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Days Worked'), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Expense'));
    await tester.pumpAndSettle();

    expect(entries.createdWorkerId, 'worker_1');
    expect(entries.createdProjectId, 'project_1');
    expect(entries.createdDaysWorked, 2);
    expect(entries.createdDailyWage, 120);
  });

  testWidgets(
    'duplicate last expense prefills amount and category without attachments',
    (tester) async {
      await tester.pumpWidget(
        _screen(
          locale: const Locale('en'),
          projectId: 'project_1',
          duplicateFrom: Expense(
            id: 'expense_last',
            workspaceId: 'workspace_1',
            projectId: 'project_1',
            projectName: 'Tower',
            category: AccountingCategories.materials,
            amount: 42.5,
            currency: 'EGP',
            date: DateTime.utc(2026, 1, 1),
            notes: 'old notes',
            supplierName: '',
            entityId: 'entity_1',
            entityName: 'Steel Co',
            paymentMethod: 'cash',
            inputMethod: 'manual',
            transcript: '',
            source: '',
            storagePath: '',
            isArchived: false,
            attachments: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('42.50'), findsWidgets);
      expect(find.text('receipt.jpg'), findsNothing);
    },
  );

  // ------------------------------------------------ feature 005: items (US1)

  testWidgets('title field comes first, above project and category', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(_screen(locale: const Locale('en')));
    await tester.pumpAndSettle();
    final title = tester.getTopLeft(
      find.byKey(const Key('qa_add_expense_title')),
    );
    final category = tester.getTopLeft(
      find.byKey(const Key('qa_add_expense_category')),
    );
    expect(title.dy, lessThan(category.dy));
  });

  testWidgets('a three-item receipt saves its items, total and title', (
    tester,
  ) async {
    _tallView(tester);
    final repo = _FakeExpenseRepository();
    await tester.pumpWidget(
      _screen(
        locale: const Locale('en'),
        projectId: 'project_1',
        expenseRepository: repo,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('qa_add_expense_title')),
      'سباكه شهر 10',
    );
    await _pickCategory(tester, AccountingCategories.materials);
    expect(find.byKey(const Key('qa_item_name_1')), findsNothing);
    await _fillItems(tester, const [
      ('حنفية', '100'),
      ('جلبه', '50'),
      ('ماسورة', '90'),
    ]);
    expect(find.text('240.00 EGP'), findsOneWidget);

    await _tapSave(tester);

    expect(repo.lastCreate, isNotNull);
    expect(repo.lastCreate!['amount'], 240);
    expect(repo.lastCreate!['description'], 'سباكه شهر 10');
    final items = repo.lastCreate!['items']! as List<Map<String, dynamic>>;
    expect(items.map((i) => (i['name'], i['amount'])), [
      ('حنفية', 100.0),
      ('جلبه', 50.0),
      ('ماسورة', 90.0),
    ]);
  });

  testWidgets('an empty title becomes the first item name', (tester) async {
    _tallView(tester);
    final repo = _FakeExpenseRepository();
    await tester.pumpWidget(
      _screen(
        locale: const Locale('en'),
        projectId: 'project_1',
        expenseRepository: repo,
      ),
    );
    await tester.pumpAndSettle();
    await _pickCategory(tester, AccountingCategories.materials);
    await _fillItems(tester, const [('أسمنت', '1500')]);
    await _tapSave(tester);
    expect(repo.lastCreate!['description'], 'أسمنت');
    expect(repo.lastCreate!['amount'], 1500);
    expect((repo.lastCreate!['items']! as List), hasLength(1));
  });

  testWidgets('an item without a name blocks saving and is marked', (
    tester,
  ) async {
    _tallView(tester);
    final repo = _FakeExpenseRepository();
    await tester.pumpWidget(
      _screen(
        locale: const Locale('en'),
        projectId: 'project_1',
        expenseRepository: repo,
      ),
    );
    await tester.pumpAndSettle();
    await _pickCategory(tester, AccountingCategories.materials);
    await tester.enterText(find.byKey(const Key('qa_item_amount_0')), '80');
    await tester.pumpAndSettle();
    await _tapSave(tester);
    expect(repo.lastCreate, isNull);
    expect(find.text(_en.t('itemNameRequired')), findsOneWidget);
  });

  testWidgets('worker category hides the title and the items editor', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(_screen(locale: const Locale('en')));
    await tester.pumpAndSettle();
    await _pickCategory(tester, AccountingCategories.worker);
    expect(find.byKey(const Key('qa_add_expense_items')), findsNothing);
    expect(find.byKey(const Key('qa_add_expense_title')), findsNothing);
  });

  testWidgets('rate × quantity only drives a single-item receipt', (
    tester,
  ) async {
    _tallView(tester);
    final contractor = AppEntity(
      id: 'contractor_1',
      workspaceId: 'workspace_1',
      name: 'BuildCo',
      normalizedName: 'buildco',
      type: AccountingEntityTypes.contractor,
      createdAt: DateTime(2026),
      defaultRate: 200,
      rateUnit: 'day',
    );
    await tester.pumpWidget(
      _screen(
        locale: const Locale('en'),
        entityRepository: _FakeEntityRepository([contractor]),
      ),
    );
    await tester.pumpAndSettle();
    await _pickCategory(tester, AccountingCategories.contractor);
    await tester.tap(find.widgetWithText(TextField, 'Entity name (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BuildCo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '3');
    await tester.pumpAndSettle();
    expect(find.text('600.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa_items_add')));
    await tester.pumpAndSettle();
    expect(find.text(_en.t('autoRateSingleItemOnly')), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '5');
    await tester.pumpAndSettle();
    expect(find.text('1,000.00'), findsNothing, reason: 'no auto amount');
  });

  testWidgets('duplicating copies the title and items with new ids', (
    tester,
  ) async {
    _tallView(tester);
    final repo = _FakeExpenseRepository();
    await tester.pumpWidget(
      _screen(
        locale: const Locale('en'),
        projectId: 'project_1',
        expenseRepository: repo,
        duplicateFrom: _plumbingExpense(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('سباكه شهر 10'), findsOneWidget);
    expect(find.byKey(const Key('qa_item_name_2')), findsOneWidget);
    await _tapSave(tester);
    final items = repo.lastCreate!['items']! as List<Map<String, dynamic>>;
    expect(items, hasLength(3));
    expect(items.map((i) => i['id']), isNot(contains('item_a')));
    expect(repo.lastCreate!['amount'], 240);
  });

  // ---------------------------------- feature 005: paste + organize (US2b)

  group('paste + organize', () {
    const plumbing = ExpenseProposal(
      title: 'سباكه شهر 10',
      items: [
        ProposalItem(name: 'حنفية', amount: 100),
        ProposalItem(name: 'جلبه', amount: 50),
        ProposalItem(name: 'ماسورة', amount: 90),
      ],
      category: 'materials',
      entityName: 'ورشة حسن',
      paymentStatus: 'paid',
      projectId: 'other_project',
    );

    testWidgets('organizing fills the form and saves it as text input', (
      tester,
    ) async {
      _tallView(tester);
      final repo = _FakeExpenseRepository();
      await tester.pumpWidget(
        _screen(
          locale: const Locale('en'),
          projectId: 'project_1',
          expenseRepository: repo,
          organizer: _FakeOrganizer(plumbing),
          entityRepository: _FakeEntityRepository([_hassan]),
        ),
      );
      await tester.pumpAndSettle();
      await _pasteAndOrganize(tester);

      final title = tester.widget<TextField>(
        find.byKey(const Key('qa_add_expense_title')),
      );
      expect(title.controller!.text, 'سباكه شهر 10');
      expect(find.text('240.00 EGP'), findsOneWidget);

      await _tapSave(tester);
      final created = repo.lastCreate!;
      expect(created['projectId'], 'project_1', reason: 'chosen project kept');
      expect(created['amount'], 240);
      expect(created['inputMethod'], 'text');
      expect(created['transcript'], _pasted);
      expect(created['source'], 'llm');
      expect(created['paymentStatus'], 'paid');
      expect(created['entityName'], 'ورشة حسن');
    });

    testWidgets('typed rows and a typed title are kept; AI rows come after', (
      tester,
    ) async {
      _tallView(tester);
      final repo = _FakeExpenseRepository();
      await tester.pumpWidget(
        _screen(
          locale: const Locale('en'),
          projectId: 'project_1',
          expenseRepository: repo,
          organizer: _FakeOrganizer(plumbing),
          entityRepository: _FakeEntityRepository([_hassan]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('qa_add_expense_title')),
        'عنواني',
      );
      await _pickCategory(tester, AccountingCategories.materials);
      await _fillItems(tester, const [('سلك', '30')]);
      await _pasteAndOrganize(tester);

      await _tapSave(tester);
      final created = repo.lastCreate!;
      expect(created['description'], 'عنواني');
      final items = created['items']! as List<Map<String, dynamic>>;
      expect(items.map((i) => i['name']), ['سلك', 'حنفية', 'جلبه', 'ماسورة']);
      expect(created['amount'], 270);
    });

    testWidgets('several-receipts and mismatch notices show on the form', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _screen(
          locale: const Locale('en'),
          projectId: 'project_1',
          organizer: _FakeOrganizer(
            const ExpenseProposal(
              title: 'سباكه',
              items: [ProposalItem(name: 'حنفية', amount: 100)],
              statedTotal: 150,
              totalMismatch: true,
              multipleReceiptsSuspected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _pasteAndOrganize(tester);
      expect(
        find.byKey(const Key('qa_add_expense_multiple_receipts')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('qa_add_expense_total_mismatch')),
        findsOneWidget,
      );
    });

    testWidgets('the paste action is hidden for the worker category', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(_screen(locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('qa_add_expense_paste')), findsOneWidget);
      await _pickCategory(tester, AccountingCategories.worker);
      expect(find.byKey(const Key('qa_add_expense_paste')), findsNothing);
    });
  });

  // ------------------------------------------- feature 005: edit items (US3)

  group('edit mode', () {
    testWidgets('pre-fills the title and the items in stored order', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _screen(
          locale: const Locale('en'),
          expenseId: 'e_plumbing',
          expenseRepository: _FakeExpenseRepository(stored: _plumbingExpense()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('سباكه شهر 10'), findsOneWidget);
      for (final (i, name) in const ['حنفية', 'جلبه', 'ماسورة'].indexed) {
        final field = tester.widget<TextField>(
          find.byKey(Key('qa_item_name_$i')),
        );
        expect(field.controller!.text, name);
      }
    });

    testWidgets('editing an amount and adding a row updates items and total', (
      tester,
    ) async {
      _tallView(tester);
      final repo = _FakeExpenseRepository(stored: _plumbingExpense());
      await tester.pumpWidget(
        _screen(
          locale: const Locale('en'),
          expenseId: 'e_plumbing',
          expenseRepository: repo,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('qa_item_amount_2')), '95');
      await tester.tap(find.byKey(const Key('qa_items_add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('qa_item_name_3')),
        'شريط تيفلون',
      );
      await tester.enterText(find.byKey(const Key('qa_item_amount_3')), '10');
      await tester.pumpAndSettle();
      await _tapSave(tester);

      expect(repo.lastUpdate!['amount'], 255);
      expect(repo.lastUpdate!['description'], 'سباكه شهر 10');
      final items = repo.lastUpdate!['items']! as List<Map<String, dynamic>>;
      expect(items, hasLength(4));
      expect(items.first['id'], 'item_a', reason: 'stored ids kept');
    });

    testWidgets('the last row cannot be removed', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(
        _screen(
          locale: const Locale('en'),
          expenseId: 'e_plumbing',
          expenseRepository: _FakeExpenseRepository(stored: _plumbingExpense()),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('qa_item_remove_0')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('qa_item_name_0')), findsOneWidget);
      expect(find.text(_en.t('cannotRemoveLastItem')), findsOneWidget);
    });

    testWidgets('a legacy expense opens as one row and saves it as an item', (
      tester,
    ) async {
      _tallView(tester);
      final repo = _FakeExpenseRepository(
        stored: _plumbingExpense(items: const [], description: 'أسمنت'),
      );
      await tester.pumpWidget(
        _screen(
          locale: const Locale('en'),
          expenseId: 'e_plumbing',
          expenseRepository: repo,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('qa_item_name_1')), findsNothing);
      await _tapSave(tester);
      final items = repo.lastUpdate!['items']! as List<Map<String, dynamic>>;
      expect(items.single['name'], 'أسمنت');
      expect(items.single['amount'], 240);
      expect(items.single['id'], isNot('legacy'));
    });
  });
}

final _en = AppLocalizations(const Locale('en'));

final _hassan = AppEntity(
  id: 'e_hassan',
  workspaceId: 'workspace_1',
  name: 'ورشة حسن',
  normalizedName: 'ورشة حسن',
  type: AccountingEntityTypes.supplier,
  createdAt: DateTime(2026),
);

class _AcceptedDisclosure implements VoiceAiDisclosureStore {
  @override
  bool get hasAccepted => true;

  @override
  Future<void> accept() async {}
}

class _FakeOrganizer implements ExpenseTextOrganizer {
  _FakeOrganizer(this.proposal);

  final ExpenseProposal proposal;

  @override
  Future<ExpenseTextOrganizeResult> organize({
    required String workspaceId,
    required String text,
    required String currency,
  }) async {
    return ExpenseTextOrganizeResult(
      text: text.trim(),
      proposal: proposal,
      source: 'llm',
    );
  }
}

const _pasted =
    'فاتورة سباكه شهر 10\n100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة';

Future<void> _pasteAndOrganize(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('qa_add_expense_paste')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('qa_paste_text')), _pasted);
  await tester.pump();
  await tester.tap(find.byKey(const Key('qa_organize_ai')));
  await tester.pumpAndSettle();
}

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pickCategory(WidgetTester tester, String category) async {
  await tester.tap(find.byKey(const Key('qa_add_expense_category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_en.expenseCategoryLabel(category)).last);
  await tester.pumpAndSettle();
}

Future<void> _fillItems(
  WidgetTester tester,
  List<(String, String)> rows,
) async {
  for (final (i, (name, amount)) in rows.indexed) {
    if (i > 0) {
      await tester.tap(find.byKey(const Key('qa_items_add')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byKey(Key('qa_item_name_$i')), name);
    await tester.enterText(find.byKey(Key('qa_item_amount_$i')), amount);
    await tester.pumpAndSettle();
  }
}

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.byKey(const Key('qa_add_expense_save'));
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Expense _plumbingExpense({
  List<ExpenseItem> items = const [
    ExpenseItem(id: 'item_a', name: 'حنفية', amount: 100),
    ExpenseItem(id: 'item_b', name: 'جلبه', amount: 50),
    ExpenseItem(id: 'item_c', name: 'ماسورة', amount: 90),
  ],
  String description = 'سباكه شهر 10',
}) {
  return Expense(
    id: 'e_plumbing',
    workspaceId: 'workspace_1',
    projectId: 'project_1',
    projectName: 'Tower',
    category: AccountingCategories.materials,
    amount: 240,
    currency: 'EGP',
    date: DateTime.utc(2026, 10, 1),
    notes: '',
    description: description,
    supplierName: '',
    paymentMethod: 'cash',
    inputMethod: 'manual',
    transcript: '',
    source: '',
    storagePath: '',
    isArchived: false,
    attachments: const [],
    items: items,
  );
}

Widget _screen({
  required Locale locale,
  EntityRepository? entityRepository,
  WorkerRepository? workerRepository,
  WorkerEntryRepository? workerEntryRepository,
  String? projectId,
  Expense? duplicateFrom,
  String? expenseId,
  _FakeExpenseRepository? expenseRepository,
  ExpenseTextOrganizer? organizer,
}) {
  return ProviderScope(
    overrides: [
      if (organizer != null)
        expenseTextOrganizerProvider.overrideWithValue(organizer),
      voiceAiDisclosureStoreProvider.overrideWithValue(_AcceptedDisclosure()),
      isOfflineProvider.overrideWithValue(false),
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      activeUserIdProvider.overrideWith((ref) => 'user_1'),
      expenseRepositoryProvider.overrideWithValue(
        expenseRepository ?? _FakeExpenseRepository(),
      ),
      // Contacts come from the local replica in the app; tests use a fake.
      entityRepositoryProvider.overrideWithValue(
        entityRepository ?? const _FakeEntityRepository([]),
      ),
      if (workerRepository != null)
        workerRepositoryProvider.overrideWithValue(workerRepository),
      if (workerEntryRepository != null)
        workerEntryRepositoryProvider.overrideWithValue(workerEntryRepository),
      projectsProvider.overrideWith((ref) => Stream.value(const [])),
      currentUserSettingsProvider.overrideWith(
        (ref) => Stream.value(
          UserSettings.defaults(userId: 'user_1', email: 'user@test.com'),
        ),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: AddExpenseScreen(
        expenseId: expenseId,
        projectId: projectId,
        duplicateFrom: duplicateFrom,
      ),
    ),
  );
}

class _FakeEntityRepository implements EntityRepository {
  const _FakeEntityRepository(this.entities);

  final List<AppEntity> entities;

  @override
  Future<AppEntity> createEntity({
    required String workspaceId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  }) async {
    return entities.first;
  }

  @override
  Future<void> deleteEntity(String entityId) async {}

  @override
  Future<AppEntity?> ensureEntity({
    required String workspaceId,
    required String name,
    String? type,
  }) async {
    return entities.firstWhere((entity) => entity.name == name);
  }

  @override
  Future<RecordPage<AppEntity>> fetchEntityDirectoryPage(
    String workspaceId, {
    required String type,
    EntityDirectorySort sort = EntityDirectorySort.recent,
    Object? cursor,
    int pageSize = 20,
  }) async {
    return RecordPage(
      items: entities.where((entity) => entity.type == type).toList(),
      hasMore: false,
    );
  }

  @override
  Future<AppEntity?> getEntityById(String entityId) async {
    return entities.firstWhere((entity) => entity.id == entityId);
  }

  @override
  Future<AppEntity?> getEntityByName(
    String workspaceId,
    String name, {
    String? type,
  }) async {
    return entities.firstWhere((entity) => entity.name == name);
  }

  @override
  Future<void> saveAttachments({
    required String entityId,
    required List<Map<String, dynamic>> attachments,
  }) async {}

  @override
  Future<List<AppEntity>> searchEntities(
    String workspaceId,
    String query, {
    String? type,
    int limit = 20,
  }) async {
    return entities
        .where((entity) => entity.workspaceId == workspaceId)
        .where((entity) => type == null || entity.type == type)
        .where((entity) => entity.normalizedName.contains(query.toLowerCase()))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<AppEntity> updateEntity({
    required String entityId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  }) async {
    return entities.first;
  }

  @override
  Stream<List<AppEntity>> watchEntities(
    String workspaceId, {
    String? type,
    int limit = 20,
  }) {
    return Stream.value(entities);
  }
}

class _FakeWorkerRepository implements WorkerRepository {
  const _FakeWorkerRepository(this.workers);

  final List<WorkerProfile> workers;

  @override
  Future<void> archiveWorker(String workerId) async {}

  @override
  Future<void> createWorker({
    required String workspaceId,
    required String userId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    WorkerStatus status = WorkerStatus.active,
  }) async {}

  @override
  Future<RecordPage<WorkerProfile>> fetchWorkersPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
    Set<WorkerStatus>? statuses,
  }) async {
    return RecordPage(items: workers, hasMore: false);
  }

  @override
  Future<WorkerProfile?> getWorker(String workerId) async {
    return workers.firstWhere((worker) => worker.id == workerId);
  }

  @override
  Future<void> updateWorker({
    required String workerId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    WorkerStatus? status,
  }) async {}

  @override
  Stream<List<WorkerProfile>> watchWorkers(
    String workspaceId, {
    Set<WorkerStatus>? statuses,
  }) {
    return Stream.value(workers);
  }
}

class _FakeWorkerEntryRepository implements WorkerEntryRepository {
  String? createdWorkerId;
  String? createdProjectId;
  double? createdDaysWorked;
  double? createdDailyWage;

  @override
  Future<MutationResult> archiveEntry(String entryId) async {
    return const MutationResult();
  }

  @override
  Future<MutationResult> createEntry({
    required String workspaceId,
    required String userId,
    required String workerId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
    List<Attachment>? attachments,
    double? projectTotalExpensesBefore,
  }) async {
    createdWorkerId = workerId;
    createdProjectId = projectId;
    createdDaysWorked = daysWorked;
    createdDailyWage = dailyWage;
    return const MutationResult();
  }

  @override
  Future<WorkerEntryRecord?> getEntry(String entryId) async => null;

  @override
  Future<void> updateEntry({
    required String entryId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
    List<Attachment>? attachments,
  }) async {}

  @override
  Stream<List<WorkerEntryRecord>> watchEntriesByWorker({
    required String workspaceId,
    required String workerId,
  }) {
    return const Stream.empty();
  }
}
