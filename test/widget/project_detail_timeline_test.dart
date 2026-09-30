import 'dart:async';

import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/project_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.controller);

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
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage<Project>(items: [], hasMore: false);
  }

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    Object? cursor,
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

Project _project({
  DateTime? startDate,
  DateTime? expectedEndDate,
  String status = 'active',
}) {
  return Project(
    id: 'project_1',
    workspaceId: 'workspace_test',
    name: 'Project Alpha',
    clientName: 'Client One',
    contractValue: 10000,
    status: status,
    completionPercentage: 40,
    totalExpenses: 1000,
    totalPayments: 2000,
    netProfit: 1000,
    isArchived: false,
    startDate: startDate,
    expectedEndDate: expectedEndDate,
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

Future<void> _pump(
  WidgetTester tester,
  StreamController<Project?> controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(
          _FakeProjectRepository(controller),
        ),
        projectRecentTransactionsProvider.overrideWith(
          (ref, scope) => Stream.value(const <DashboardTransactionRef>[]),
        ),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
}

void main() {
  testWidgets(
    'shows days-remaining timeline text and ~50% elapsed for a project '
    'midway between start and expected end',
    (tester) async {
      final controller = StreamController<Project?>();
      addTearDown(controller.close);

      await _pump(tester, controller);

      final now = DateTime.now();
      controller.add(
        _project(
          startDate: now.subtract(const Duration(days: 30)),
          expectedEndDate: now.add(const Duration(days: 30)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('qa_project_detail_timeline')),
        findsOneWidget,
      );
      // 30 (or 29, depending on time-of-day truncation) days remaining.
      final daysRemainingFinder = find.textContaining('Days Remaining');
      expect(daysRemainingFinder, findsOneWidget);
      final text = tester.widget<Text>(daysRemainingFinder).data!;
      expect(text, anyOf(contains('29'), contains('30'), contains('31')));

      // ~50% of the timeline elapsed.
      final elapsedFinder = find.textContaining('Timeline Elapsed');
      expect(elapsedFinder, findsOneWidget);
      final elapsedText = tester.widget<Text>(elapsedFinder).data!;
      expect(
        elapsedText,
        anyOf(
          contains('49%'),
          contains('50%'),
          contains('51%'),
        ),
      );
    },
  );

  testWidgets(
    'omits the timeline block entirely when either date is missing',
    (tester) async {
      final controller = StreamController<Project?>();
      addTearDown(controller.close);

      await _pump(tester, controller);

      controller.add(
        _project(startDate: DateTime.now(), expectedEndDate: null),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('qa_project_detail_timeline')),
        findsNothing,
      );
      expect(find.textContaining('Days Remaining'), findsNothing);
      expect(find.textContaining('Overdue'), findsNothing);
    },
  );

  testWidgets(
    'shows "Overdue" messaging when past the expected end date and the '
    'project is not marked completed',
    (tester) async {
      final controller = StreamController<Project?>();
      addTearDown(controller.close);

      await _pump(tester, controller);

      final now = DateTime.now();
      controller.add(
        _project(
          startDate: now.subtract(const Duration(days: 60)),
          expectedEndDate: now.subtract(const Duration(days: 10)),
          status: 'active',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Overdue'), findsOneWidget);
      expect(find.textContaining('Days Remaining'), findsNothing);
    },
  );

  testWidgets(
    'omits the days-remaining/overdue line for a completed project past '
    'its expected end date',
    (tester) async {
      final controller = StreamController<Project?>();
      addTearDown(controller.close);

      await _pump(tester, controller);

      final now = DateTime.now();
      controller.add(
        _project(
          startDate: now.subtract(const Duration(days: 60)),
          expectedEndDate: now.subtract(const Duration(days: 10)),
          status: 'completed',
        ),
      );
      await tester.pumpAndSettle();

      // The timeline concept is moot once a project is completed: no
      // "Overdue by N Days" and no raw negative "N Days Remaining" either.
      expect(find.textContaining('Overdue'), findsNothing);
      expect(find.textContaining('Days Remaining'), findsNothing);

      // The card itself (with its elapsed-schedule progress bar) still
      // renders — only the now-moot days-remaining/overdue line is gone.
      expect(
        find.byKey(const Key('qa_project_detail_timeline')),
        findsOneWidget,
      );
    },
  );
}
