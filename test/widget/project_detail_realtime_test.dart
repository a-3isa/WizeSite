import 'dart:async';

import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/widgets/ds/hero_net_card.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/project_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _RealtimeProjectRepository implements ProjectRepository {
  _RealtimeProjectRepository(this.controller);

  final StreamController<Project?> controller;

  @override
  Future<void> archiveProject(String projectId) async {}

  @override
  Future<MutationResult> createProject({
    required String workspaceId,
    required String userId,
    required String name,
    required String clientName,
    required double contractValue,
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
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage<Project>(items: [], hasMore: false);
  }

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage<Project>(items: [], hasMore: false);
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
    required double contractValue,
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

Project _project({
  required String name,
  required String clientName,
  required double totalExpenses,
  double? budgetLimit,
}) {
  return Project(
    id: 'project_1',
    workspaceId: 'workspace_test',
    name: name,
    clientName: clientName,
    contractValue: 10000,
    status: 'active',
    completionPercentage: 40,
    totalExpenses: totalExpenses,
    totalPayments: 8000,
    netProfit: 2000 - totalExpenses,
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

void main() {
  testWidgets('ProjectDetailScreen updates when the project stream changes', (
    tester,
  ) async {
    final controller = StreamController<Project?>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectRepositoryProvider.overrideWithValue(
            _RealtimeProjectRepository(controller),
          ),
          projectRecentTransactionsProvider.overrideWith(
            (ref, scope) => Stream.value(const <DashboardTransactionRef>[]),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );

    controller.add(
      _project(
        name: 'Project Alpha',
        clientName: 'Client One',
        totalExpenses: 1500,
      ),
    );
    await tester.pumpAndSettle();

    // Project name/client come from the (unchanged) ProjectHeader; the
    // financial numbers now come from the v2 hero net card's income/expense
    // split (raw formatted numbers, currency shown once on the net figure).
    expect(find.text('Project Alpha'), findsOneWidget);
    expect(find.text('Client One'), findsOneWidget);
    expect(find.text('500'), findsOneWidget); // net = 2000 - 1500 (profit)
    expect(find.text('1,500'), findsOneWidget); // expense split value

    controller.add(
      _project(
        name: 'Project Beta',
        clientName: 'Client Two',
        totalExpenses: 3200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project Alpha'), findsNothing);
    expect(find.text('Client One'), findsNothing);
    expect(find.text('Project Beta'), findsOneWidget);
    expect(find.text('Client Two'), findsOneWidget);
    expect(find.text('−1,200'), findsOneWidget); // net = 2000 - 3200 (loss)
    expect(find.text('3,200'), findsOneWidget); // expense split value
  });

  testWidgets(
    'budget hero shows remaining amount, color-graded by usage',
    (tester) async {
      final controller = StreamController<Project?>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectRepositoryProvider.overrideWithValue(
              _RealtimeProjectRepository(controller),
            ),
            projectRecentTransactionsProvider.overrideWith(
              (ref, scope) => Stream.value(const <DashboardTransactionRef>[]),
            ),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );

      // 50% used (budgetLimit: 2000, spent: 1000): income (green) band, with
      // the 1,000 remaining amount always shown — even well below the
      // warning threshold, so the card never looks "empty" at low usage.
      controller.add(
        _project(
          name: 'Project Alpha',
          clientName: 'Client One',
          totalExpenses: 1000,
          budgetLimit: 2000,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Remaining', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('1,000', skipOffstage: false), findsWidgets);
      var remainingText = tester.widget<Text>(
        find.textContaining('Remaining', skipOffstage: false),
      );
      expect(remainingText.style?.color, BuildTokens.light.income);

      // 95% used (budgetLimit: 2000, spent: 1900): expense (red) band.
      controller.add(
        _project(
          name: 'Project Alpha',
          clientName: 'Client One',
          totalExpenses: 1900,
          budgetLimit: 2000,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Remaining', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('100', skipOffstage: false), findsWidgets);
      remainingText = tester.widget<Text>(
        find.textContaining('Remaining', skipOffstage: false),
      );
      expect(remainingText.style?.color, BuildTokens.light.expense);

      // Contract Value is demoted to a compact, muted secondary row (per
      // the v2 UI audit) — guard against it being re-inflated back to
      // prominent styling.
      final contractValueRow = find.byKey(
        const Key('qa_project_detail_contract_value'),
        skipOffstage: false,
      );
      expect(contractValueRow, findsOneWidget);
      final contractValueText = tester.widget<Text>(
        find
            .descendant(of: contractValueRow, matching: find.byType(Text))
            .last,
      );
      expect(contractValueText.style?.fontSize, 12);
      expect(contractValueText.style?.fontWeight, FontWeight.w700);
      expect(contractValueText.style?.color, BuildTokens.light.textMuted);

      // Ordering: the demoted Contract Value row must render after the Net
      // Profit hero card, never re-promoted above it.
      final heroDy = tester
          .getTopLeft(find.byType(HeroNetCard, skipOffstage: false))
          .dy;
      final contractValueDy = tester.getTopLeft(contractValueRow).dy;
      expect(contractValueDy, greaterThan(heroDy));
    },
  );
}
