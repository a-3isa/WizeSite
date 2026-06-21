import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
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

    expect(find.text('Highest expense'), findsOneWidget);
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
