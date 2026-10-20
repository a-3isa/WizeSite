import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/session_restore_service.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_proposal.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/voice_expense/data/voice_expense_repository.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/screens/voice_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockSessionRestoreService extends Mock
    implements SessionRestoreService {}

class _MockVoiceExpenseRepository extends Mock
    implements VoiceExpenseRepository {}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<bool> hasAnyPayment(String projectId) async => false;

  @override
  Future<void> archiveProject(String projectId) async {}

  @override
  Future<MutationResult> createProject({
    required String workspaceId,
    required String userId,
    required String name,
    required String clientName,
    double? contractValue,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    double completionPercentage = 0,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<RecordPage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    cursor,
    int pageSize = 20,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<RecordPage<Project>> fetchProjectsPage(
    String workspaceId, {
    cursor,
    int pageSize = 20,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Project?> getProject(String projectId) async {
    return null;
  }

  @override
  Future<void> unarchiveProject(String projectId) async {}

  @override
  Future<void> updateProject({
    required String projectId,
    required String name,
    required String clientName,
    double? contractValue,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    double? completionPercentage,
    String? status,
  }) async {}

  @override
  Stream<List<Project>> watchAllProjects(String workspaceId) {
    return const Stream.empty();
  }

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) {
    return const Stream.empty();
  }

  @override
  Stream<Project?> watchProject(String projectId) {
    return const Stream.empty();
  }

  @override
  Stream<List<Project>> watchProjects(String workspaceId) {
    return const Stream.empty();
  }
}

GoRouter _router(Widget child) {
  return GoRouter(
    initialLocation: '/review',
    routes: [
      GoRoute(path: '/review', builder: (context, state) => child),
      GoRoute(
        path: '/project/:projectId/expenses',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Project Expenses Screen')),
        ),
      ),
    ],
  );
}

VoiceExpenseParseResponse _response() {
  return const VoiceExpenseParseResponse(
    transcript: 'cement purchase',
    parsed: VoiceParsedExpense(
      amount: 1250,
      currency: 'EGP',
      category: 'materials',
      matchedProjectId: 'project_1',
      matchedProjectName: 'Tower A',
      note: 'cement',
    ),
    confidence: VoiceConfidenceScores(
      amount: 0.9,
      category: 0.8,
      project: 0.95,
      overall: 0.88,
    ),
    source: 'rules',
    needsConfirmation: true,
    storagePath: 'voice/path.m4a',
  );
}

void main() {
  testWidgets(
    'VoiceReviewScreen restores workspace before saving confirmed expense',
    (tester) async {
      final sessionRestoreService = _MockSessionRestoreService();
      final voiceRepository = _MockVoiceExpenseRepository();

      when(() => sessionRestoreService.restore()).thenAnswer(
        (_) async => const SessionRestoreResult(
          userId: 'user_1',
          workspaceId: 'workspace_1',
          setupCompleted: true,
        ),
      );
      when(
        () => voiceRepository.saveConfirmedVoiceExpense(
          workspaceId: any(named: 'workspaceId'),
          projectId: any(named: 'projectId'),
          projectName: any(named: 'projectName'),
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          category: any(named: 'category'),
          notes: any(named: 'notes'),
          transcript: any(named: 'transcript'),
          source: any(named: 'source'),
          storagePath: any(named: 'storagePath'),
          date: any(named: 'date'),
          items: any(named: 'items'),
          description: any(named: 'description'),
          entityId: any(named: 'entityId'),
          entityName: any(named: 'entityName'),
          paymentStatus: any(named: 'paymentStatus'),
        ),
      ).thenAnswer((_) async => 'expense_1');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => null),
            activeUserIdProvider.overrideWith((ref) => null),
            sessionRestoreServiceProvider.overrideWithValue(
              sessionRestoreService,
            ),
            voiceExpenseRepositoryProvider.overrideWithValue(voiceRepository),
            projectRepositoryProvider.overrideWithValue(
              _FakeProjectRepository(),
            ),
            currentUserSettingsProvider.overrideWith(
              (ref) => Stream.value(
                UserSettings.defaults(userId: 'user_1', email: 'u@test.com'),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: _router(
              VoiceReviewScreen(
                response: _response(),
                projects: const [
                  VoiceProjectOption(id: 'project_1', name: 'Tower A'),
                ],
              ),
            ),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Review Voice Expense'), findsOneWidget);
      final confirmButton = find.text('Confirm & Save');
      await tester.scrollUntilVisible(
        confirmButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(confirmButton, findsOneWidget);
      await tester.tap(confirmButton);
      await tester.pump();
      await tester.pumpAndSettle();

      verify(() => sessionRestoreService.restore()).called(1);
      verify(
        () => voiceRepository.saveConfirmedVoiceExpense(
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          projectName: 'Tower A',
          amount: 1250,
          currency: 'EGP',
          category: 'materials',
          notes: 'cement',
          transcript: 'cement purchase',
          source: 'rules',
          storagePath: 'voice/path.m4a',
          date: any(named: 'date'),
          items: any(named: 'items'),
          description: 'cement',
          entityId: any(named: 'entityId'),
          entityName: any(named: 'entityName'),
          paymentStatus: 'unpaid',
        ),
      ).called(1);
      expect(find.text('Project Expenses Screen'), findsOneWidget);
    },
  );

  // ------------------------------------------- feature 005: AI proposal (US2)

  testWidgets('a proposal fills the title, three item rows and the fields', (
    tester,
  ) async {
    final repo = _savingRepository();
    await _pumpReview(tester, repo, _proposalResponse());

    expect(_fieldText(tester, 'qa_voice_review_title'), 'سباكه شهر 10');
    expect(_fieldText(tester, 'qa_item_name_2'), 'ماسورة');
    expect(find.byKey(const Key('qa_item_name_3')), findsNothing);
    expect(find.text('240.00 EGP'), findsOneWidget);
    expect(_fieldText(tester, 'qa_voice_review_supplier'), 'ورشة حسن');
    expect(find.text('Paid'), findsOneWidget);

    await _confirm(tester);
    final saved = _captureSave(repo);
    expect(saved['amount'], 240);
    expect(saved['description'], 'سباكه شهر 10');
    expect(saved['source'], 'llm');
    expect(saved['paymentStatus'], 'paid');
    expect(saved['entityId'], 'e_hassan');
    final items = saved['items']! as List<Map<String, dynamic>>;
    expect(items.map((i) => i['name']), ['حنفية', 'جلبه', 'ماسورة']);
  });

  testWidgets('a flagged row blocks saving until it is fixed', (tester) async {
    final repo = _savingRepository();
    await _pumpReview(
      tester,
      repo,
      _proposalResponse(
        items: const [
          ProposalItem(name: 'حنفية', amount: 100),
          ProposalItem(name: null, amount: 50, needsReview: true),
        ],
      ),
    );
    expect(find.byKey(const Key('qa_item_review_1')), findsOneWidget);
    await _confirm(tester);
    _verifyNoSave(repo);

    await tester.enterText(find.byKey(const Key('qa_item_name_1')), 'جلبه');
    await tester.pumpAndSettle();
    await _confirm(tester);
    expect(_captureSave(repo)['amount'], 150);
  });

  testWidgets('mismatch and several-receipts notices are shown', (
    tester,
  ) async {
    await _pumpReview(
      tester,
      _savingRepository(),
      _proposalResponse(
        statedTotal: 250,
        totalMismatch: true,
        multipleReceiptsSuspected: true,
      ),
    );
    expect(
      find.byKey(const Key('qa_voice_review_total_mismatch')),
      findsOneWidget,
    );
    expect(find.textContaining('250.00'), findsOneWidget);
    expect(
      find.byKey(const Key('qa_voice_review_multiple_receipts')),
      findsOneWidget,
    );
  });

  testWidgets('a single item with no title proposes the item as the title', (
    tester,
  ) async {
    await _pumpReview(
      tester,
      _savingRepository(),
      _proposalResponse(
        title: null,
        items: const [ProposalItem(name: 'رمل', amount: 2000)],
      ),
    );
    expect(_fieldText(tester, 'qa_voice_review_title'), 'رمل');
  });

  testWidgets('a title-only proposal shows one flagged empty row', (
    tester,
  ) async {
    final repo = _savingRepository();
    await _pumpReview(
      tester,
      repo,
      _proposalResponse(title: 'سباكه', items: const []),
    );
    expect(_fieldText(tester, 'qa_voice_review_title'), 'سباكه');
    expect(find.byKey(const Key('qa_item_name_0')), findsOneWidget);
    expect(find.byKey(const Key('qa_item_name_1')), findsNothing);
    expect(find.byKey(const Key('qa_item_review_0')), findsOneWidget);
    await _confirm(tester);
    _verifyNoSave(repo);
  });

  testWidgets('without a proposal (older server) one row comes from parsed', (
    tester,
  ) async {
    final repo = _savingRepository();
    await _pumpReview(tester, repo, _response());
    expect(_fieldText(tester, 'qa_item_name_0'), 'cement');
    expect(_fieldText(tester, 'qa_item_amount_0'), '1,250.00');
    await _confirm(tester);
    final saved = _captureSave(repo);
    expect(saved['amount'], 1250);
    expect((saved['items']! as List).single['name'], 'cement');
  });
}

VoiceExpenseParseResponse _proposalResponse({
  String? title = 'سباكه شهر 10',
  List<ProposalItem> items = const [
    ProposalItem(name: 'حنفية', amount: 100),
    ProposalItem(name: 'جلبه', amount: 50),
    ProposalItem(name: 'ماسورة', amount: 90),
  ],
  double? statedTotal,
  bool totalMismatch = false,
  bool multipleReceiptsSuspected = false,
}) {
  return VoiceExpenseParseResponse(
    transcript:
        'فاتورة سباكه شهر 10، 100 جنيه حنفية، 50 جنيه جلبه، 90 جنيه ماسورة',
    parsed: const VoiceParsedExpense(
      amount: 240,
      currency: 'EGP',
      category: 'materials',
      matchedProjectId: 'project_1',
      matchedProjectName: 'Tower A',
      note: 'سباكه شهر 10',
    ),
    confidence: const VoiceConfidenceScores(
      amount: 0.9,
      category: 0.8,
      project: 0.85,
      overall: 0.85,
    ),
    source: 'llm',
    needsConfirmation: true,
    storagePath: 'voice/path.m4a',
    proposal: ExpenseProposal(
      title: title,
      items: items,
      projectId: 'project_1',
      projectName: 'Tower A',
      category: 'materials',
      entityId: 'e_hassan',
      entityName: 'ورشة حسن',
      paymentStatus: 'paid',
      statedTotal: statedTotal,
      totalMismatch: totalMismatch,
      multipleReceiptsSuspected: multipleReceiptsSuspected,
    ),
  );
}

_MockVoiceExpenseRepository _savingRepository() {
  final repo = _MockVoiceExpenseRepository();
  when(
    () => repo.saveConfirmedVoiceExpense(
      workspaceId: any(named: 'workspaceId'),
      projectId: any(named: 'projectId'),
      projectName: any(named: 'projectName'),
      amount: any(named: 'amount'),
      currency: any(named: 'currency'),
      category: any(named: 'category'),
      notes: any(named: 'notes'),
      transcript: any(named: 'transcript'),
      source: any(named: 'source'),
      storagePath: any(named: 'storagePath'),
      date: any(named: 'date'),
      items: any(named: 'items'),
      description: any(named: 'description'),
      entityId: any(named: 'entityId'),
      entityName: any(named: 'entityName'),
      paymentStatus: any(named: 'paymentStatus'),
    ),
  ).thenAnswer((_) async => 'expense_1');
  return repo;
}

/// Named arguments of the single save call.
Map<String, Object?> _captureSave(_MockVoiceExpenseRepository repo) {
  final captured = verify(
    () => repo.saveConfirmedVoiceExpense(
      workspaceId: any(named: 'workspaceId'),
      projectId: any(named: 'projectId'),
      projectName: any(named: 'projectName'),
      amount: captureAny(named: 'amount'),
      currency: any(named: 'currency'),
      category: any(named: 'category'),
      notes: any(named: 'notes'),
      transcript: any(named: 'transcript'),
      source: captureAny(named: 'source'),
      storagePath: any(named: 'storagePath'),
      date: any(named: 'date'),
      items: captureAny(named: 'items'),
      description: captureAny(named: 'description'),
      entityId: captureAny(named: 'entityId'),
      entityName: any(named: 'entityName'),
      paymentStatus: captureAny(named: 'paymentStatus'),
    ),
  ).captured;
  return {
    'amount': captured[0],
    'source': captured[1],
    'items': captured[2],
    'description': captured[3],
    'entityId': captured[4],
    'paymentStatus': captured[5],
  };
}

void _verifyNoSave(_MockVoiceExpenseRepository repo) {
  verifyNever(
    () => repo.saveConfirmedVoiceExpense(
      workspaceId: any(named: 'workspaceId'),
      projectId: any(named: 'projectId'),
      projectName: any(named: 'projectName'),
      amount: any(named: 'amount'),
      currency: any(named: 'currency'),
      category: any(named: 'category'),
      notes: any(named: 'notes'),
      transcript: any(named: 'transcript'),
      source: any(named: 'source'),
      storagePath: any(named: 'storagePath'),
      date: any(named: 'date'),
      items: any(named: 'items'),
      description: any(named: 'description'),
      entityId: any(named: 'entityId'),
      entityName: any(named: 'entityName'),
      paymentStatus: any(named: 'paymentStatus'),
    ),
  );
}

Future<void> _pumpReview(
  WidgetTester tester,
  _MockVoiceExpenseRepository repo,
  VoiceExpenseParseResponse response,
) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
        activeUserIdProvider.overrideWith((ref) => 'user_1'),
        voiceExpenseRepositoryProvider.overrideWithValue(repo),
        projectRepositoryProvider.overrideWithValue(_FakeProjectRepository()),
        currentUserSettingsProvider.overrideWith(
          (ref) => Stream.value(
            UserSettings.defaults(userId: 'user_1', email: 'u@test.com'),
          ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: _router(
          VoiceReviewScreen(
            response: response,
            projects: const [
              VoiceProjectOption(id: 'project_1', name: 'Tower A'),
            ],
          ),
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

Future<void> _confirm(WidgetTester tester) async {
  final confirm = find.byKey(const Key('qa_voice_review_confirm'));
  await tester.ensureVisible(confirm);
  await tester.pumpAndSettle();
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}
