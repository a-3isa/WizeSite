import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/widgets/ds/hero_net_card.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/project_detail_screen.dart';
import 'package:buildtrack_app/features/projects/presentation/widgets/project_details_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Expense-ledger mode: a project with no Contract Value hides the whole
/// revenue side and explains why, while every expense-side affordance keeps
/// working. Also pins the inverse — a contract-bearing project must look
/// exactly as it did before this feature existed (FR-018).
class _StreamProjectRepository implements ProjectRepository {
  _StreamProjectRepository(this.controller);

  final StreamController<Project?> controller;

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
    return const MutationResult();
  }

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<RecordPage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
  }) async {
    return const RecordPage<Project>(items: [], hasMore: false);
  }

  @override
  Future<RecordPage<Project>> fetchProjectsPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
  }) async {
    return const RecordPage<Project>(items: [], hasMore: false);
  }

  @override
  Future<Project?> getProject(String projectId) async => null;

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
    return const Stream<List<Project>>.empty();
  }

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) {
    return const Stream<List<Project>>.empty();
  }

  @override
  Stream<Project?> watchProject(String projectId) => controller.stream;

  @override
  Stream<List<Project>> watchProjects(String workspaceId) {
    return const Stream<List<Project>>.empty();
  }
}

Project _project({double? contractValue, double? budgetLimit}) {
  return Project(
    id: 'project_1',
    workspaceId: 'workspace_test',
    name: 'Project Alpha',
    clientName: 'Client One',
    contractValue: contractValue,
    status: 'active',
    completionPercentage: 40,
    totalExpenses: 1500,
    totalPayments: 0,
    netProfit: -1500,
    isArchived: false,
    budgetLimit: budgetLimit,
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/project/project_1',
    routes: [
      GoRoute(
        path: '/projects',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/project/:id',
        builder: (context, state) =>
            ProjectDetailScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/project/:id/edit',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/project/:projectId/expenses',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/payments',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/workers',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/add-expense',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/add-payment',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/worker-entry/:id',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
}

Future<void> _pumpProject(
  WidgetTester tester,
  Project project, {
  Locale? locale,
}) async {
  // The detail screen scrolls lazily, so a default-sized viewport never builds
  // the action grid near the bottom. A tall surface builds the whole page.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = StreamController<Project?>();
  addTearDown(controller.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(
          _StreamProjectRepository(controller),
        ),
        projectRecentTransactionsProvider.overrideWith(
          (ref, scope) => Stream.value(const <DashboardTransactionRef>[]),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: _router(),
        locale: locale,
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

  controller.add(project);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('project with no contract value hides the whole revenue side', (
    tester,
  ) async {
    await _pumpProject(tester, _project());

    // Revenue-side widgets and actions are gone.
    expect(find.byType(HeroNetCard), findsNothing);
    expect(
      find.byKey(const Key('qa_project_detail_profit_margin')),
      findsNothing,
    );
    // The action grid sits below the fold in a lazy scroll view, so assert on
    // its wiring rather than on rendered children.
    expect(
      tester.widget<ActionGrid>(find.byType(ActionGrid)).showPaymentActions,
      isFalse,
    );

    // Contract row omitted rather than rendered as a zero amount.
    expect(
      find.byKey(const Key('qa_project_detail_contract_value')),
      findsNothing,
    );

    // The headline states expenses instead of a net profit built from no income.
    expect(
      find.byKey(const Key('qa_project_detail_expense_total')),
      findsOneWidget,
    );
  });

  testWidgets('the empty-state explains the absence and offers a way out', (
    tester,
  ) async {
    await _pumpProject(tester, _project());

    // Asserted by presence, not by the absence of revenue widgets — an
    // absence-only check would also pass if the empty-state were never built.
    expect(
      find.byKey(const Key('qa_project_detail_no_contract_empty_state')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('qa_project_detail_set_contract_value')),
      findsOneWidget,
    );
    expect(find.text('No contract value set'), findsOneWidget);
  });

  testWidgets('expense-side affordances keep working in expense-ledger mode', (
    tester,
  ) async {
    await _pumpProject(tester, _project());

    // The mode hides revenue, never the cost-tracking the project exists for.
    // Only the payment actions are suppressed; every other action is untouched.
    final grid = tester.widget<ActionGrid>(find.byType(ActionGrid));
    expect(grid.showPaymentActions, isFalse);
    expect(grid.onAddExpense, isNotNull);
    expect(grid.onViewExpenses, isNotNull);
    expect(grid.onAddWorkerEntry, isNotNull);
    expect(grid.onViewWorkers, isNotNull);
    expect(grid.onGenerateReport, isNotNull);
    expect(grid.onEdit, isNotNull);
    expect(grid.onArchive, isNotNull);
  });

  testWidgets(
    'a budget limit shows budget widgets while revenue stays hidden',
    (tester) async {
      await _pumpProject(tester, _project(budgetLimit: 5000));

      // The two switches are independent: a spending budget with no income
      // expected is a coherent, intended combination.
      expect(find.text('Budget used'), findsOneWidget);
      expect(find.byType(HeroNetCard), findsNothing);
      expect(
        tester.widget<ActionGrid>(find.byType(ActionGrid)).showPaymentActions,
        isFalse,
      );
    },
  );

  testWidgets(
    'adding a contract value restores budget and revenue widgets against '
    'existing expenses',
    (tester) async {
      final controller = StreamController<Project?>();
      addTearDown(controller.close);

      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectRepositoryProvider.overrideWithValue(
              _StreamProjectRepository(controller),
            ),
            projectRecentTransactionsProvider.overrideWith(
              (ref, scope) => Stream.value(const <DashboardTransactionRef>[]),
            ),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );

      // Starts as an expense ledger with 1500 of expenses already recorded.
      controller.add(_project());
      await tester.pumpAndSettle();
      expect(find.byType(HeroNetCard), findsNothing);
      expect(find.text('Budget used'), findsNothing);

      // The user sets a contract value of 2000.
      controller.add(_project(contractValue: 2000));
      await tester.pumpAndSettle();

      // Budget progress must reflect the pre-existing expenses (1500/2000 =
      // 75%), not restart at 0%.
      expect(find.text('Budget used'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      // The revenue side returns in the same step.
      expect(find.byType(HeroNetCard), findsOneWidget);
      expect(
        tester.widget<ActionGrid>(find.byType(ActionGrid)).showPaymentActions,
        isTrue,
      );
      expect(
        find.byKey(const Key('qa_project_detail_no_contract_empty_state')),
        findsNothing,
      );
    },
  );

  testWidgets('the empty-state renders in Arabic with RTL direction', (
    tester,
  ) async {
    await _pumpProject(tester, _project(), locale: const Locale('ar'));

    final l10n = AppLocalizations(const Locale('ar'));
    final title = find.text(l10n.t('noContractValueTitle'));

    // The localization system falls back to English silently, so asserting the
    // Arabic string is present is what catches a missing translation.
    expect(title, findsOneWidget);
    expect(find.text(l10n.t('setContractValue')), findsOneWidget);
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);
  });

  testWidgets('a contract-bearing project is unchanged by this feature', (
    tester,
  ) async {
    await _pumpProject(tester, _project(contractValue: 10000));

    expect(find.byType(HeroNetCard), findsOneWidget);
    expect(
      find.byKey(const Key('qa_project_detail_profit_margin')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('qa_project_detail_contract_value')),
      findsOneWidget,
    );
    expect(
      tester.widget<ActionGrid>(find.byType(ActionGrid)).showPaymentActions,
      isTrue,
    );
    expect(
      find.byKey(const Key('qa_project_detail_no_contract_empty_state')),
      findsNothing,
    );
  });
}
