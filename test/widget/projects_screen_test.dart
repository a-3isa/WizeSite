import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/archived_projects_screen.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Project _project(String id, double net, {String status = 'active'}) {
  return Project(
    id: id,
    workspaceId: 'workspace_1',
    name: 'Project $id',
    clientName: 'Client',
    contractValue: 1000,
    status: status,
    completionPercentage: 50,
    totalExpenses: 500,
    totalPayments: 500 + net,
    netProfit: net,
    isArchived: false,
  );
}

class _FakeProjectRepository
    implements ProjectRepository, ProjectBrowseRepository {
  _FakeProjectRepository({
    required this.firstPage,
    this.secondPage = const FirestorePage<Project>(items: [], hasMore: false),
  });

  final FirestorePage<Project> firstPage;
  final FirestorePage<Project> secondPage;
  final queries = <ProjectBrowseQuery>[];
  final archivedIds = <String>[];

  @override
  Future<FirestorePage<Project>> fetchProjectBrowsePage(
    ProjectBrowseQuery request, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    queries.add(request);
    return cursor == null ? firstPage : secondPage;
  }

  @override
  Future<void> archiveProject(String projectId) async {
    archivedIds.add(projectId);
  }

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
  }) async => const MutationResult();

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async => const FirestorePage(items: [], hasMore: false);

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async => cursor == null ? firstPage : secondPage;

  @override
  Future<Project?> getProject(String projectId) async => null;

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
  Stream<List<Project>> watchAllProjects(String workspaceId) =>
      const Stream.empty();

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) =>
      const Stream.empty();

  @override
  Stream<Project?> watchProject(String projectId) => const Stream.empty();

  @override
  Stream<List<Project>> watchProjects(String workspaceId) =>
      const Stream.empty();
}

Future<DocumentSnapshot<Map<String, dynamic>>> _cursor() async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('cursors').doc('page_1').set({'value': 1});
  return firestore.collection('cursors').doc('page_1').get();
}

Widget _app(ProjectRepository repository, AccountingAccessRoleType role) {
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      projectRepositoryProvider.overrideWithValue(repository),
      currentAccountingRoleProvider.overrideWith((ref) => Stream.value(role)),
      currentUserSettingsProvider.overrideWith(
        (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProjectsScreen(),
    ),
  );
}

Widget _archivedApp(ProjectRepository repository) {
  final router = GoRouter(
    initialLocation: '/projects/archived',
    routes: [
      GoRoute(
        path: '/projects',
        builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/projects/archived',
        builder: (_, _) => const ArchivedProjectsScreen(),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      projectRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp.router(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('shows loading content while the first project page resolves', (
    tester,
  ) async {
    final repository = _PendingProjectRepository();

    await tester.pumpWidget(_app(repository, AccountingAccessRoleType.owner));
    await tester.pump();

    expect(find.byType(AppLoadingSkeleton), findsOneWidget);
    expect(find.text('Project high'), findsNothing);

    repository.completeFirstPage(
      FirestorePage(items: [_project('high', 500)], hasMore: false),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppLoadingSkeleton), findsNothing);
    expect(find.text('Project high'), findsOneWidget);
  });

  testWidgets('shows loading content while archived projects resolve', (
    tester,
  ) async {
    final repository = _PendingArchivedProjectRepository();

    await tester.pumpWidget(_archivedApp(repository));
    await tester.pump();

    expect(find.byType(AppLoadingSkeleton), findsOneWidget);
    expect(find.text('Project old'), findsNothing);

    repository.completeFirstPage(
      FirestorePage(items: [_project('old', 0)], hasMore: false),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppLoadingSkeleton), findsNothing);
    expect(find.text('Project old'), findsOneWidget);
  });

  testWidgets('owner can page, filter, and use financial project sorts', (
    tester,
  ) async {
    final repository = _FakeProjectRepository(
      firstPage: FirestorePage(
        items: [
          _project('high', 500),
          _project('loss', -100),
          ...List.generate(
            18,
            (index) => _project('middle_$index', 100 + index.toDouble()),
          ),
        ],
        hasMore: true,
        nextCursor: await _cursor(),
      ),
      secondPage: FirestorePage(items: [_project('tail', 50)], hasMore: false),
    );

    await tester.pumpWidget(_app(repository, AccountingAccessRoleType.owner));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('qa_projects_sort')));
    await tester.pumpAndSettle();
    expect(find.text('Highest expense'), findsOneWidget);
    await tester.tap(find.text('Highest expense'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.sort, ProjectBrowseSort.highestExpense);
    expect(find.byIcon(Icons.trending_up), findsWidgets);
    expect(find.byIcon(Icons.trending_down), findsOneWidget);
    expect(find.textContaining('500'), findsWidgets);

    await tester.fling(
      find.byType(ListView).last,
      const Offset(0, -5000),
      3000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Project tail'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa_projects_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.status, 'completed');
  });

  testWidgets('member sees recent/name browse without financial values', (
    tester,
  ) async {
    final repository = _FakeProjectRepository(
      firstPage: FirestorePage(
        items: [_project('hidden', 9999)],
        hasMore: false,
      ),
    );

    await tester.pumpWidget(_app(repository, AccountingAccessRoleType.member));
    await tester.pumpAndSettle();

    expect(find.text('Highest expense'), findsNothing);
    expect(find.textContaining('Financial project details'), findsOneWidget);
    expect(find.textContaining('9,999'), findsNothing);
    expect(
      repository.queries.every((query) => !query.sort.isFinancial),
      isTrue,
    );
  });

  testWidgets('archive requires confirmation before mutation', (tester) async {
    final repository = _FakeProjectRepository(
      firstPage: FirestorePage(
        items: [_project('archive_me', 100)],
        hasMore: false,
      ),
    );

    await tester.pumpWidget(_app(repository, AccountingAccessRoleType.owner));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();

    expect(find.text('Archive this project?'), findsOneWidget);
    expect(repository.archivedIds, isEmpty);

    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();
    expect(repository.archivedIds, ['archive_me']);
  });
}

class _PendingProjectRepository extends _FakeProjectRepository {
  _PendingProjectRepository()
    : _firstPageCompleter = Completer<FirestorePage<Project>>(),
      super(firstPage: const FirestorePage(items: [], hasMore: false));

  final Completer<FirestorePage<Project>> _firstPageCompleter;

  @override
  Future<FirestorePage<Project>> fetchProjectBrowsePage(
    ProjectBrowseQuery request, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) {
    queries.add(request);
    if (cursor != null) {
      return Future.value(secondPage);
    }
    return _firstPageCompleter.future;
  }

  void completeFirstPage(FirestorePage<Project> page) {
    _firstPageCompleter.complete(page);
  }
}

class _PendingArchivedProjectRepository extends _FakeProjectRepository {
  _PendingArchivedProjectRepository()
    : _firstPageCompleter = Completer<FirestorePage<Project>>(),
      super(firstPage: const FirestorePage(items: [], hasMore: false));

  final Completer<FirestorePage<Project>> _firstPageCompleter;

  @override
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) {
    if (cursor != null) {
      return Future.value(const FirestorePage(items: [], hasMore: false));
    }
    return _firstPageCompleter.future;
  }

  void completeFirstPage(FirestorePage<Project> page) {
    _firstPageCompleter.complete(page);
  }
}
