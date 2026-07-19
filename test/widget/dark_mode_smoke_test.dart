import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/app_theme.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart'
    show AccountingAccessRoleType;
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/activity/presentation/screens/activity_screen.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/add_expense_screen.dart';
import 'package:buildtrack_app/features/notifications/data/notification_providers.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/add_payment_screen.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/more_screen.dart';
import 'package:buildtrack_app/features/subscription/domain/entitlement_guard_service.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_repository.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_quota_repository.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// Guards that the dark theme is wired end-to-end: a widget reading
/// `context.tokens` resolves the dark palette when the app runs in dark mode,
/// and every primary screen renders without throwing under
/// `themeMode: ThemeMode.dark`.

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

class _FakeExpenseRepository implements ExpenseRepository {
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
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage(items: [], hasMore: false);
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
    return const Stream.empty();
  }
}

class _FakePaymentRepository implements PaymentRepository {
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
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    double? projectTotalPaymentsBefore,
    List<Attachment>? attachments,
  }) async {
    return const MutationResult(queued: false);
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
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage(items: [], hasMore: false);
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
    return const Stream.empty();
  }
}

class _FakeSubscriptionRepository implements SubscriptionRepository {
  @override
  Future<SubscriptionState> getSubscription(String workspaceId) async {
    return SubscriptionState.free();
  }

  @override
  Stream<SubscriptionState> watchSubscription(String workspaceId) {
    return Stream.value(SubscriptionState.free());
  }
}

class _FakeUsageQuotaRepository implements UsageQuotaRepository {
  @override
  Future<LimitCheckResult> checkLimit({
    required String workspaceId,
    required LimitType type,
    required int delta,
  }) async {
    return LimitCheckResult(
      allowed: true,
      limitType: type,
      current: 0,
      max: 10,
    );
  }

  @override
  Future<UsageSnapshot> getUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) async {
    return UsageSnapshot.empty(limits: limits);
  }

  @override
  Stream<UsageSnapshot> watchUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) {
    return Stream.value(UsageSnapshot.empty(limits: limits));
  }
}

class _FakeProjectRepository
    implements ProjectRepository, ProjectBrowseRepository {
  @override
  Future<FirestorePage<Project>> fetchProjectBrowsePage(
    ProjectBrowseQuery request, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async => const FirestorePage(items: [], hasMore: false);

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
  Future<FirestorePage<Project>> fetchProjectsPage(
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

const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  testWidgets('dark theme resolves dark tokens through context', (
    tester,
  ) async {
    late BuildTokens resolved;
    late Color scaffoldBg;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(const Locale('en')),
        darkTheme: AppTheme.dark(const Locale('en')),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            resolved = context.tokens;
            scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    expect(resolved, BuildTokens.dark);
    expect(scaffoldBg, BuildTokens.dark.bg);
    expect(resolved.text, BuildTokens.dark.text);
  });

  testWidgets('light theme resolves light tokens through context', (
    tester,
  ) async {
    late BuildTokens resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(const Locale('en')),
        darkTheme: AppTheme.dark(const Locale('en')),
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (context) {
            resolved = context.tokens;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    expect(resolved, BuildTokens.light);
  });

  group('dark-mode screen smoke test', () {
    Widget wrap({required Widget home, GoRouter? router}) {
      if (router != null) {
        return MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(const Locale('en')),
          darkTheme: AppTheme.dark(const Locale('en')),
          themeMode: ThemeMode.dark,
          localizationsDelegates: _delegates,
          supportedLocales: AppLocalizations.supportedLocales,
        );
      }
      return MaterialApp(
        theme: AppTheme.light(const Locale('en')),
        darkTheme: AppTheme.dark(const Locale('en')),
        themeMode: ThemeMode.dark,
        localizationsDelegates: _delegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      );
    }

    testWidgets('Home (DashboardScreen) renders without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            dashboardSnapshotProvider.overrideWith(
              (ref, workspaceId) =>
                  Stream.value(DashboardSnapshot.restricted()),
            ),
            notificationItemsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            unreadNotificationCountProvider.overrideWith((ref) => 0),
            currentUsageProvider.overrideWith(
              (ref) =>
                  Stream.value(UsageSnapshot.empty(limits: PlanLimits.free())),
            ),
            currentSubscriptionStreamProvider.overrideWith(
              (ref) => Stream.value(SubscriptionState.free()),
            ),
            currentUserSettingsProvider.overrideWith(
              (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
            ),
          ],
          child: wrap(home: const DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Projects (ProjectsScreen) renders without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            projectRepositoryProvider.overrideWithValue(
              _FakeProjectRepository(),
            ),
            currentAccountingRoleProvider.overrideWith(
              (ref) => Stream.value(AccountingAccessRoleType.owner),
            ),
            currentUserSettingsProvider.overrideWith(
              (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
            ),
          ],
          child: wrap(home: const ProjectsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Activity (ActivityScreen) renders without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'ws1'),
            dashboardWeeklyInsightsProvider('ws1').overrideWith(
              (ref) => Stream.value(
                DashboardWeeklyInsights(
                  topEntity: '',
                  topCategory: '',
                  laborTotal: 0,
                  equipmentTotal: 0,
                  paymentSummary: const {},
                  recentTransactions: const [],
                ),
              ),
            ),
          ],
          child: wrap(home: const ActivityScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('More (MoreScreen) renders without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(child: wrap(home: const MoreScreen())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add expense (AddExpenseScreen) renders without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            activeUserIdProvider.overrideWith((ref) => 'user_1'),
            expenseRepositoryProvider.overrideWithValue(
              _FakeExpenseRepository(),
            ),
            projectsProvider.overrideWith((ref) => Stream.value(const [])),
            currentUserSettingsProvider.overrideWith(
              (ref) => Stream.value(
                UserSettings.defaults(userId: 'user_1', email: 'user@test.com'),
              ),
            ),
          ],
          child: wrap(home: const AddExpenseScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add payment (AddPaymentScreen) renders without exception', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: AppRoutes.addPaymentPath(projectId: 'project_1'),
        routes: [
          GoRoute(
            path: AppRoutes.addPayment,
            builder: (context, state) => AddPaymentScreen(
              projectId: state.uri.queryParameters['projectId'],
            ),
          ),
          GoRoute(
            path: AppRoutes.subscriptionLimit,
            builder: (context, state) => Text(
              'limit:${state.uri.queryParameters['limit']}',
              textDirection: TextDirection.ltr,
            ),
          ),
          GoRoute(
            path: AppRoutes.projectDetail,
            builder: (context, state) =>
                const Text('Project Detail', textDirection: TextDirection.ltr),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            activeUserIdProvider.overrideWith((ref) => 'user_1'),
            paymentRepositoryProvider.overrideWithValue(
              _FakePaymentRepository(),
            ),
            projectsProvider.overrideWith(
              (ref) => Stream.value(const [
                Project(
                  id: 'project_1',
                  workspaceId: 'workspace_1',
                  name: 'Project One',
                  clientName: 'Client',
                  contractValue: 1000,
                  status: 'active',
                  completionPercentage: 0,
                  totalExpenses: 0,
                  totalPayments: 0,
                  netProfit: 0,
                  isArchived: false,
                ),
              ]),
            ),
            entitlementGuardProvider.overrideWithValue(
              EntitlementGuardService(
                subscriptionRepository: _FakeSubscriptionRepository(),
                usageQuotaRepository: _FakeUsageQuotaRepository(),
              ),
            ),
          ],
          child: wrap(router: router, home: const SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Login (LoginScreen) renders without exception', (
      tester,
    ) async {
      final auth = _MockFirebaseAuth();
      final workspaceService = _MockWorkspaceMutationService();
      final router = GoRouter(
        initialLocation: AppRoutes.login,
        routes: [
          GoRoute(
            path: AppRoutes.login,
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) =>
                const Text('Dashboard', textDirection: TextDirection.ltr),
          ),
          GoRoute(
            path: AppRoutes.initialWorkspaceSetup,
            builder: (context, state) => const Text(
              'Workspace Setup',
              textDirection: TextDirection.ltr,
            ),
          ),
          GoRoute(
            path: AppRoutes.verifyEmail,
            builder: (context, state) =>
                const Text('Verify Email', textDirection: TextDirection.ltr),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            workspaceMutationServiceProvider.overrideWithValue(
              workspaceService,
            ),
            googleSignInSupportedProvider.overrideWith(
              (ref) => Future.value(false),
            ),
            activeUserIdProvider.overrideWith((ref) => null),
            activeWorkspaceIdProvider.overrideWith((ref) => null),
          ],
          child: wrap(router: router, home: const SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
