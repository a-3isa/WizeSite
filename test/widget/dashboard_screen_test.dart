import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/notifications/data/notification_providers.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('restricted dashboard never renders financial totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        DashboardFinancialSection(
          snapshot: DashboardSnapshot.restricted(),
          currency: 'EGP',
          locale: 'en',
        ),
      ),
    );

    expect(
      find.byKey(const Key('dashboard_financial_restricted')),
      findsOneWidget,
    );
    expect(find.textContaining('1,000'), findsNothing);
  });

  testWidgets('profit and loss meaning is not conveyed by color alone', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromMap({
      'totalExpenses': 1000,
      'totalIncome': 500,
      'weeklyExpenses': 100,
      'weeklyIncome': 50,
    });
    await tester.pumpWidget(
      _app(
        DashboardFinancialSection(
          snapshot: snapshot,
          currency: 'EGP',
          locale: 'en',
        ),
      ),
    );

    expect(find.byIcon(Icons.trending_down), findsWidgets);
    expect(find.byKey(const Key('dashboard_net_loss')), findsOneWidget);
  });

  testWidgets('workspace switcher persists selected workspace', (tester) async {
    final workspaceService = _MockWorkspaceMutationService();
    when(
      () => workspaceService.setActiveWorkspace(workspaceId: 'shared_ws'),
    ).thenAnswer((_) async => 'shared_ws');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'personal_ws'),
          userWorkspaceSummariesProvider.overrideWith(
            (ref) => Stream.value(const [
              WorkspaceSummary(
                id: 'personal_ws',
                name: 'Personal Workspace',
                role: 'owner',
                isOwnedByCurrentUser: true,
              ),
              WorkspaceSummary(
                id: 'shared_ws',
                name: 'Shared Workspace',
                role: 'member',
                isOwnedByCurrentUser: false,
              ),
            ]),
          ),
          workspaceMutationServiceProvider.overrideWithValue(workspaceService),
        ],
        child: _app(const WorkspaceSwitcher()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('qa_workspace_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared Workspace').last);
    await tester.pumpAndSettle();

    verify(
      () => workspaceService.setActiveWorkspace(workspaceId: 'shared_ws'),
    ).called(1);
  });

  testWidgets(
    'workspace switcher uses active workspace doc name before summaries load',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('workspaces').doc('workspace_1').set({
        'name': 'Acme Sites',
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(firestore),
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            userWorkspaceSummariesProvider.overrideWith(
              (ref) => Stream.value(const <WorkspaceSummary>[]),
            ),
          ],
          child: _app(const WorkspaceSwitcher()),
        ),
      );
      await tester.pump();

      expect(find.text('Acme Sites'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    },
  );

  testWidgets('workspace switcher rolls back when persistence fails', (
    tester,
  ) async {
    final workspaceService = _MockWorkspaceMutationService();
    when(
      () => workspaceService.setActiveWorkspace(workspaceId: 'shared_ws'),
    ).thenThrow(Exception('switch failed'));
    final container = ProviderContainer(
      overrides: [
        activeWorkspaceIdProvider.overrideWith((ref) => 'personal_ws'),
        userWorkspaceSummariesProvider.overrideWith(
          (ref) => Stream.value(const [
            WorkspaceSummary(
              id: 'personal_ws',
              name: 'Personal Workspace',
              role: 'owner',
              isOwnedByCurrentUser: true,
            ),
            WorkspaceSummary(
              id: 'shared_ws',
              name: 'Shared Workspace',
              role: 'member',
              isOwnedByCurrentUser: false,
            ),
          ]),
        ),
        workspaceMutationServiceProvider.overrideWithValue(workspaceService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const WorkspaceSwitcher()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('qa_workspace_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared Workspace').last);
    await tester.pumpAndSettle();

    expect(container.read(activeWorkspaceIdProvider), 'personal_ws');
  });

  testWidgets('dashboard shows resources instead of quick actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          dashboardSnapshotProvider.overrideWith(
            (ref, workspaceId) => Stream.value(DashboardSnapshot.restricted()),
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
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resources'), findsOneWidget);
    expect(find.byKey(const Key('qa_resource_workers')), findsOneWidget);
    expect(find.byKey(const Key('qa_resource_contractors')), findsOneWidget);
    expect(find.byKey(const Key('qa_add_expense')), findsNothing);
    expect(find.text('Monthly Usage'), findsNothing);
  });

  testWidgets(
    'Approach B: project selector scopes dashboard to one project '
    '(financials, 75% budget bar, recent list)',
    (tester) async {
      const project = Project(
        id: 'project_1',
        workspaceId: 'workspace_1',
        name: 'Villa Project',
        clientName: 'Owner',
        contractValue: 180000,
        status: 'active',
        completionPercentage: 0,
        totalExpenses: 135500,
        totalPayments: 220000,
        netProfit: 84500,
        isArchived: false,
        budgetLimit: 180000,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            selectedDashboardProjectIdProvider.overrideWith(
              (ref) => 'project_1',
            ),
            // Workspace-wide ("All Projects") snapshot — distinct numbers.
            dashboardSnapshotProvider.overrideWith(
              (ref, workspaceId) => Stream.value(
                DashboardSnapshot.fromMap({
                  'totalExpenses': 1000,
                  'totalIncome': 2000,
                  'activeProjects': 1,
                }),
              ),
            ),
            projectsProvider.overrideWith(
              (ref) => Stream.value(const <Project>[project]),
            ),
            projectRecentTransactionsProvider.overrideWith(
              (ref, scope) => Stream.value(<DashboardTransactionRef>[
                DashboardTransactionRef(
                  id: 'p1',
                  type: 'payment',
                  title: 'Owner deposit',
                  amount: 120000,
                  date: DateTime(2026, 6, 20),
                ),
                DashboardTransactionRef(
                  id: 'e1',
                  type: 'expense',
                  title: 'El-Nasr Supplies',
                  amount: 45000,
                  date: DateTime(2026, 6, 18),
                ),
              ]),
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
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Selector is present in the app bar and shows the project context.
      expect(
        find.byKey(const Key('qa_dashboard_project_selector')),
        findsOneWidget,
      );
      expect(find.text('Villa Project'), findsOneWidget);

      // Financial section renders below the fold in the ListView, so include
      // off-stage widgets in these finders.
      // Scope caption appears for the selected project.
      expect(
        find.byKey(
          const Key('qa_dashboard_project_scope_caption'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      // Project financials (contract value) + budget bar at 75%.
      expect(
        find.textContaining('180,000', skipOffstage: false),
        findsWidgets,
      );
      expect(find.text('75%', skipOffstage: false), findsOneWidget);
      // Project-scoped recent list with funds-in (+) and expense (-).
      expect(
        find.byKey(
          const Key('qa_dashboard_project_recent'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.text('Owner deposit', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('+120,000', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.text('El-Nasr Supplies', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('-45,000', skipOffstage: false),
        findsOneWidget,
      );
    },
  );
}
