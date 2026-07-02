import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/widgets/app_bottom_nav_shell.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/notifications/data/notification_providers.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/reports/data/report_project_selector_provider.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/domain/report_scope.dart';
import 'package:buildtrack_app/features/reports/presentation/screens/reports_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('shell destinations localize into RTL Arabic semantics', (
    tester,
  ) async {
    final l10n = AppLocalizations(const Locale('ar'));
    final router = GoRouter(
      initialLocation: AppRoutes.dashboard,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              AppBottomNavShell(navigationShell: shell),
          branches: [
            for (final route in const [AppRoutes.dashboard, AppRoutes.projects])
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: route,
                    builder: (context, state) => Text(route),
                  ),
                ],
              ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          appPrefetcherProvider.overrideWithValue(
            AppPrefetcher(warm: ({required target, projectId}) {}),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
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

    expect(
      Directionality.of(tester.element(find.text(l10n.t('home')).first)),
      TextDirection.rtl,
    );
    for (final key in ['home', 'projects', 'activity', 'more']) {
      expect(find.text(l10n.t(key)), findsOneWidget);
    }
  });

  testWidgets('dashboard resources expose button semantics', (tester) async {
    await tester.pumpWidget(_dashboardApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('qa_resource_workers')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Workers',
      'Contractors',
      'Equipment providers',
      'Transport providers',
    ]) {
      final matchingSemantics = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((widget) => widget.properties.label == label)
          .toList();
      expect(matchingSemantics, hasLength(1));
      expect(matchingSemantics.single.properties.button, isTrue);
    }
  });

  testWidgets('reports export control has discoverable semantics', (
    tester,
  ) async {
    await tester.pumpWidget(_reportsApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Exports'), findsOneWidget);
    expect(find.bySemanticsLabel('Exports'), findsOneWidget);
  });

  testWidgets(
    'project cards expose status and profit/loss text, not color only',
    (tester) async {
      await tester.pumpWidget(
        _projectsApp(
          _FakeProjectRepository(
            FirestorePage(items: [_project('alpha', 125)], hasMore: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsWidgets);
      expect(find.text('Profit'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    },
  );
}

Widget _dashboardApp() {
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      unreadNotificationCountProvider.overrideWith((ref) => 0),
      currentUsageProvider.overrideWith(
        (ref) => Stream.value(UsageSnapshot.empty(limits: PlanLimits.free())),
      ),
      currentSubscriptionStreamProvider.overrideWith(
        (ref) => Stream.value(SubscriptionState.free()),
      ),
      currentUserSettingsProvider.overrideWith(
        (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
      ),
      dashboardSnapshotProvider.overrideWith(
        (ref, workspaceId) => Stream.value(
          DashboardSnapshot.fromMap({
            'totalProjects': 1,
            'activeProjects': 1,
            'totalExpenses': 10,
            'totalIncome': 20,
            'weeklyExpenses': 5,
            'weeklyIncome': 8,
          }),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DashboardScreen(),
      routes: {
        AppRoutes.addExpense: (_) => const SizedBox.shrink(),
        AppRoutes.addPayment: (_) => const SizedBox.shrink(),
        AppRoutes.workers: (_) => const SizedBox.shrink(),
        AppRoutes.createProject: (_) => const SizedBox.shrink(),
        AppRoutes.subscriptionPlans: (_) => const SizedBox.shrink(),
        AppRoutes.notifications: (_) => const SizedBox.shrink(),
        AppRoutes.settings: (_) => const SizedBox.shrink(),
        AppRoutes.syncStatus: (_) => const SizedBox.shrink(),
      },
    ),
  );
}

Widget _reportsApp() {
  final project = _project('project_1', 100);
  final selector = ReportProjectSelectorController(
    loadActivePage: ({cursor}) async =>
        FirestorePage(items: [project], hasMore: false),
    loadArchivedPage: ({cursor}) async =>
        const FirestorePage(items: [], hasMore: false),
  );

  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      activeUserIdProvider.overrideWith((ref) => 'user_1'),
      currentAccountingRoleProvider.overrideWith(
        (ref) => Stream.value(AccountingAccessRoleType.owner),
      ),
      projectsProvider.overrideWith((ref) => Stream.value([project])),
      reportProjectSelectorProvider.overrideWith((ref) => selector),
      reportProjectIdProvider.overrideWith((ref) => project.id),
      reportScopeProvider.overrideWith(
        (ref) => ReportScope.monthToDate(
          projectId: project.id,
          now: DateTime(2026, 6, 16),
        ),
      ),
      reportMetricsProvider.overrideWith(
        (ref) => AsyncData(
          ReportMetrics(
            projectId: project.id,
            projectName: project.name,
            status: project.status,
            isArchived: false,
            totalExpenses: 10,
            totalIncome: 20,
            net: 10,
            categoryTotals: const {},
            monthlyFlow: const [],
            topWorkers: const [],
            recentExpenses: const [],
            recentPayments: const [],
          ),
        ),
      ),
      currentUsageProvider.overrideWith(
        (ref) => Stream.value(UsageSnapshot.empty(limits: PlanLimits.free())),
      ),
      currentUserSettingsProvider.overrideWith(
        (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
      ),
      dashboardWeeklyInsightsProvider.overrideWith(
        (ref, workspaceId) => Stream.value(
          DashboardWeeklyInsights(
            topEntity: 'Supplier',
            topCategory: 'materials',
            laborTotal: 0,
            equipmentTotal: 0,
            paymentSummary: const {},
            recentTransactions: const [],
          ),
        ),
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
      home: ReportsScreen(projectId: 'project_1'),
    ),
  );
}

Widget _projectsApp(ProjectRepository repository) {
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      projectRepositoryProvider.overrideWithValue(repository),
      currentAccountingRoleProvider.overrideWith(
        (ref) => Stream.value(AccountingAccessRoleType.owner),
      ),
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

Project _project(String id, double net, {String status = 'active'}) {
  return Project(
    id: id,
    workspaceId: 'workspace_1',
    name: 'Project $id',
    clientName: 'Client',
    contractValue: 1000,
    status: status,
    completionPercentage: 50,
    totalExpenses: 100,
    totalPayments: 100 + net,
    netProfit: net,
    isArchived: false,
  );
}

class _FakeProjectRepository
    implements ProjectRepository, ProjectBrowseRepository {
  _FakeProjectRepository(this.page);

  final FirestorePage<Project> page;

  @override
  Future<FirestorePage<Project>> fetchProjectBrowsePage(
    ProjectBrowseQuery request, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async => page;

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async => page;

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
