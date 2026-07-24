import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/widgets/ds/hero_net_card.dart';
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
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
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
      ProviderScope(
        child: _app(
          DashboardFinancialSection(
            snapshot: DashboardSnapshot.restricted(),
            currency: 'EGP',
            locale: 'en',
            workspaceId: '',
          ),
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
      ProviderScope(
        child: _app(
          DashboardFinancialSection(
            snapshot: snapshot,
            currency: 'EGP',
            locale: 'en',
            workspaceId: '',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.trending_down), findsWidgets);
    expect(find.byKey(const Key('dashboard_net_loss')), findsOneWidget);
  });

  testWidgets(
    'profit margin KPI shows net/income as a percentage alongside the '
    'other dashboard stat tiles',
    (tester) async {
      // net = 230,000, income = 750,000 -> 230,000 / 750,000 * 100 = 30.7%.
      final snapshot = DashboardSnapshot.fromMap({
        'totalExpenses': 520000,
        'totalIncome': 750000,
        'weeklyExpenses': 0,
        'weeklyIncome': 0,
      });
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            DashboardFinancialSection(
              snapshot: snapshot,
              currency: 'EGP',
              locale: 'en',
              workspaceId: '',
            ),
          ),
        ),
      );
      // Profit Margin's value is an AnimatedCounter (v2 UI audit Task D2) --
      // let its count-up animation settle before asserting the final text.
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qa_dashboard_profit_margin')), findsOneWidget);
      expect(find.text('Profit Margin'), findsOneWidget);
      expect(find.text('30.7%'), findsOneWidget);
      final marginValue = tester.widget<Text>(find.text('30.7%'));
      expect(marginValue.style?.color, BuildTokens.light.income);
    },
  );

  testWidgets(
    'profit margin KPI shows an em dash (not NaN/Infinity) when income is zero',
    (tester) async {
      final snapshot = DashboardSnapshot.fromMap({
        'totalExpenses': 0,
        'totalIncome': 0,
        'weeklyExpenses': 0,
        'weeklyIncome': 0,
      });
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            DashboardFinancialSection(
              snapshot: snapshot,
              currency: 'EGP',
              locale: 'en',
              workspaceId: '',
            ),
          ),
        ),
      );

      final marginTile = find.byKey(const Key('qa_dashboard_profit_margin'));
      expect(marginTile, findsOneWidget);
      expect(
        find.descendant(of: marginTile, matching: find.text('—')),
        findsOneWidget,
      );
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
    },
  );

  testWidgets(
    'weekly income up 50% vs last week shows a green up-arrow trend',
    (tester) async {
      final snapshot = DashboardSnapshot.fromMap({
        'totalExpenses': 1000,
        'totalIncome': 500,
        'weeklyExpenses': 0,
        'weeklyIncome': 150000,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardPreviousWeekSummaryProvider.overrideWith(
              (ref, workspaceId) => Stream.value(const <String, num>{
                'previousWeekExpenses': 0,
                'previousWeekIncome': 100000,
              }),
            ),
          ],
          child: _app(
            DashboardFinancialSection(
              snapshot: snapshot,
              currency: 'EGP',
              locale: 'en',
              workspaceId: 'workspace_1',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.trending_up_outlined), findsOneWidget);
      expect(find.text('+50%'), findsOneWidget);
      final percentText = tester.widget<Text>(find.text('+50%'));
      expect(percentText.style?.color, BuildTokens.light.income);
    },
  );

  testWidgets(
    'weekly expenses up 50% vs last week shows a red (unfavorable) up-arrow trend',
    (tester) async {
      final snapshot = DashboardSnapshot.fromMap({
        'totalExpenses': 1000,
        'totalIncome': 500,
        'weeklyExpenses': 150000,
        'weeklyIncome': 0,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardPreviousWeekSummaryProvider.overrideWith(
              (ref, workspaceId) => Stream.value(const <String, num>{
                'previousWeekExpenses': 100000,
                'previousWeekIncome': 0,
              }),
            ),
          ],
          child: _app(
            DashboardFinancialSection(
              snapshot: snapshot,
              currency: 'EGP',
              locale: 'en',
              workspaceId: 'workspace_1',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.trending_up_outlined), findsOneWidget);
      expect(find.text('+50%'), findsOneWidget);
      final percentText = tester.widget<Text>(find.text('+50%'));
      expect(percentText.style?.color, BuildTokens.light.expense);
    },
  );

  testWidgets(
    'no trend shown when this week and last week are both zero (divide-by-zero guard)',
    (tester) async {
      final snapshot = DashboardSnapshot.fromMap({
        'totalExpenses': 1000,
        'totalIncome': 500,
        'weeklyExpenses': 0,
        'weeklyIncome': 0,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardPreviousWeekSummaryProvider.overrideWith(
              (ref, workspaceId) => Stream.value(const <String, num>{
                'previousWeekExpenses': 0,
                'previousWeekIncome': 0,
              }),
            ),
          ],
          child: _app(
            DashboardFinancialSection(
              snapshot: snapshot,
              currency: 'EGP',
              locale: 'en',
              workspaceId: 'workspace_1',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.trending_up_outlined), findsNothing);
      expect(find.byIcon(Icons.trending_down_outlined), findsNothing);
    },
  );

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
      retry: (_, _) => null,
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
    'Workers resource tile shows a live count and is visually prominent',
    (tester) async {
      final workers = List.generate(
        26,
        (i) => WorkerProfile(
          id: 'worker_$i',
          workspaceId: 'workspace_1',
          name: 'Worker $i',
          phoneNumber: '0100000000$i',
          dailyWage: 100,
          billingType: 'daily',
          workerType: 'general',
          notes: '',
          isArchived: false,
        ),
      );

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
            workersProvider.overrideWith((ref) => Stream.value(workers)),
          ],
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Live count renders next to the label.
      expect(find.text('Workers (26)'), findsOneWidget);
      // The other resource types have no count source and keep plain labels.
      expect(find.text('Contractors'), findsOneWidget);
      expect(find.text('Equipment providers'), findsOneWidget);
      expect(find.text('Transport providers'), findsOneWidget);

      // Workers renders above (before) the Contractors/Equipment/Transport
      // row in the widget tree, and with a visually larger/bolder style.
      final workersOffset = tester
          .getTopLeft(find.byKey(const Key('qa_resource_workers')))
          .dy;
      final contractorsOffset = tester
          .getTopLeft(find.byKey(const Key('qa_resource_contractors')))
          .dy;
      expect(workersOffset, lessThan(contractorsOffset));

      final workersTextStyle = tester
          .widget<Text>(find.text('Workers (26)'))
          .style;
      final contractorsTextStyle = tester
          .widget<Text>(find.text('Contractors'))
          .style;
      expect(
        workersTextStyle!.fontSize,
        greaterThan(contractorsTextStyle!.fontSize!),
      );
    },
  );

  testWidgets(
    'worker attendance summary card renders distinct worker count and '
    'man-days derived from worker_entries (UI audit Task B2)',
    (tester) async {
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
            // 3 entries this week across 2 distinct workers, totaling 5.5
            // man-days — mirrors what a real workspace + date-range scoped
            // `worker_entries` query would derive client-side.
            dashboardWorkerAttendanceProvider.overrideWith(
              (ref, workspaceId) => Stream.value(
                const WorkerAttendanceSummary(workerCount: 2, manDays: 5.5),
              ),
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

      expect(
        find.byKey(const Key('qa_worker_attendance_summary')),
        findsOneWidget,
      );
      expect(find.text('2 Workers · 5.5 Man-Days This Week'), findsOneWidget);
      expect(find.byIcon(Icons.engineering_outlined), findsWidgets);
    },
  );

  testWidgets(
    'cash collected / outstanding payments card renders derived totals from '
    'payment status (UI audit Task B3)',
    (tester) async {
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
            // `paid` + `partial` (15,000) count as collected — a one-time
            // fetch (FutureProvider); `unpaid` (5,000) counts as outstanding
            // — a status-filtered live listener (StreamProvider). Mirrors
            // what the real split Firestore reads would derive client-side.
            dashboardCashCollectedProvider.overrideWith(
              (ref, workspaceId) async => 15000,
            ),
            dashboardOutstandingPaymentsProvider.overrideWith(
              (ref, workspaceId) => Stream.value(5000),
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

      expect(
        find.byKey(const Key('qa_dashboard_payment_status_row')),
        findsOneWidget,
      );
      expect(find.text('Cash Collected'), findsOneWidget);
      expect(find.text('Outstanding Payments'), findsOneWidget);
      expect(find.text('15,000 EGP'), findsOneWidget);
      expect(find.text('5,000 EGP'), findsOneWidget);
      expect(find.byIcon(Icons.payments_outlined), findsWidgets);
      expect(find.byIcon(Icons.pending_actions_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'alerts strip shows an aggregate count when 2 of 3 projects are over '
    'budget (UI audit Task B5)',
    (tester) async {
      const overBudgetA = Project(
        id: 'project_a',
        workspaceId: 'workspace_1',
        name: 'Villa Project',
        clientName: 'Owner A',
        contractValue: 100000,
        status: 'active',
        completionPercentage: 0,
        totalExpenses: 60000,
        totalPayments: 40000,
        netProfit: -20000,
        isArchived: false,
        budgetLimit: 50000,
      );
      const overBudgetB = Project(
        id: 'project_b',
        workspaceId: 'workspace_1',
        name: 'Tower Project',
        clientName: 'Owner B',
        contractValue: 200000,
        status: 'active',
        completionPercentage: 0,
        totalExpenses: 120000,
        totalPayments: 90000,
        netProfit: -30000,
        isArchived: false,
        budgetLimit: 100000,
      );
      const onBudgetC = Project(
        id: 'project_c',
        workspaceId: 'workspace_1',
        name: 'Warehouse Project',
        clientName: 'Owner C',
        contractValue: 80000,
        status: 'active',
        completionPercentage: 0,
        totalExpenses: 20000,
        totalPayments: 30000,
        netProfit: 10000,
        isArchived: false,
        budgetLimit: 80000,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            dashboardSnapshotProvider.overrideWith(
              (ref, workspaceId) =>
                  Stream.value(DashboardSnapshot.restricted()),
            ),
            projectsProvider.overrideWith(
              (ref) => Stream.value(const <Project>[
                overBudgetA,
                overBudgetB,
                onBudgetC,
              ]),
            ),
            dashboardCashCollectedProvider.overrideWith(
              (ref, workspaceId) async => 0,
            ),
            dashboardOutstandingPaymentsProvider.overrideWith(
              (ref, workspaceId) => Stream.value(0),
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

      expect(find.byKey(const Key('qa_dashboard_alerts_card')), findsOneWidget);
      expect(find.text('2 Projects Over Budget'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsWidgets);
      // The on-budget project and the outstanding-payments row are not
      // named/rendered — only the over-budget aggregate shows.
      expect(find.textContaining('Unpaid Payments'), findsNothing);
    },
  );

  testWidgets(
    'alerts strip names a single over-budget project directly (UI audit '
    'Task B5)',
    (tester) async {
      const overBudget = Project(
        id: 'project_a',
        workspaceId: 'workspace_1',
        name: 'Villa Project',
        clientName: 'Owner A',
        contractValue: 100000,
        status: 'active',
        completionPercentage: 0,
        totalExpenses: 60000,
        totalPayments: 40000,
        netProfit: -20000,
        isArchived: false,
        budgetLimit: 50000,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            dashboardSnapshotProvider.overrideWith(
              (ref, workspaceId) =>
                  Stream.value(DashboardSnapshot.restricted()),
            ),
            projectsProvider.overrideWith(
              (ref) => Stream.value(const <Project>[overBudget]),
            ),
            dashboardCashCollectedProvider.overrideWith(
              (ref, workspaceId) async => 0,
            ),
            dashboardOutstandingPaymentsProvider.overrideWith(
              (ref, workspaceId) => Stream.value(0),
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

      expect(find.byKey(const Key('qa_dashboard_alerts_card')), findsOneWidget);
      expect(find.text('Villa Project: Over Budget'), findsOneWidget);
    },
  );

  testWidgets(
    'alerts strip shows an unpaid-payments attention item derived from '
    "Task B3's outstanding-payments provider (UI audit Task B5)",
    (tester) async {
      const onBudget = Project(
        id: 'project_a',
        workspaceId: 'workspace_1',
        name: 'Villa Project',
        clientName: 'Owner A',
        contractValue: 100000,
        status: 'active',
        completionPercentage: 0,
        totalExpenses: 10000,
        totalPayments: 40000,
        netProfit: 30000,
        isArchived: false,
        budgetLimit: 50000,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            dashboardSnapshotProvider.overrideWith(
              (ref, workspaceId) =>
                  Stream.value(DashboardSnapshot.restricted()),
            ),
            projectsProvider.overrideWith(
              (ref) => Stream.value(const <Project>[onBudget]),
            ),
            dashboardCashCollectedProvider.overrideWith(
              (ref, workspaceId) async => 15000,
            ),
            dashboardOutstandingPaymentsProvider.overrideWith(
              (ref, workspaceId) => Stream.value(5000),
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

      expect(find.byKey(const Key('qa_dashboard_alerts_card')), findsOneWidget);
      expect(find.text('Unpaid Payments: 5,000 EGP'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      // No over-budget project in this scenario, so no budget alert row.
      expect(find.textContaining('Over Budget'), findsNothing);
    },
  );

  testWidgets(
    "alerts strip is omitted entirely when there's nothing to flag (no "
    'empty "0 alerts" clutter) (UI audit Task B5)',
    (tester) async {
      const onBudget = Project(
        id: 'project_a',
        workspaceId: 'workspace_1',
        name: 'Villa Project',
        clientName: 'Owner A',
        contractValue: 100000,
        status: 'active',
        completionPercentage: 0,
        totalExpenses: 10000,
        totalPayments: 40000,
        netProfit: 30000,
        isArchived: false,
        budgetLimit: 50000,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            dashboardSnapshotProvider.overrideWith(
              (ref, workspaceId) =>
                  Stream.value(DashboardSnapshot.restricted()),
            ),
            projectsProvider.overrideWith(
              (ref) => Stream.value(const <Project>[onBudget]),
            ),
            dashboardCashCollectedProvider.overrideWith(
              (ref, workspaceId) async => 0,
            ),
            dashboardOutstandingPaymentsProvider.overrideWith(
              (ref, workspaceId) => Stream.value(0),
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

      expect(find.byKey(const Key('qa_dashboard_alerts_card')), findsNothing);
      expect(find.text('Alerts'), findsNothing);
    },
  );

  testWidgets('Approach B: project selector scopes dashboard to one project '
      '(financials, 75% budget bar, recent list)', (tester) async {
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
          selectedDashboardProjectIdProvider.overrideWith((ref) => 'project_1'),
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
    expect(find.textContaining('180,000', skipOffstage: false), findsWidgets);
    expect(find.text('75%', skipOffstage: false), findsOneWidget);
    // 75% used sits in the warning band (70-90%): remaining amount is shown
    // (180,000 - 135,500 = 44,500) and color-graded to match.
    expect(
      find.textContaining('44,500', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Remaining', skipOffstage: false),
      findsOneWidget,
    );
    final percentText = tester.widget<Text>(
      find.text('75%', skipOffstage: false),
    );
    expect(percentText.style?.color, BuildTokens.light.warning);
    // Project-scoped recent list with funds-in (+) and expense (-).
    expect(
      find.byKey(const Key('qa_dashboard_project_recent'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Owner deposit', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('+120,000', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('El-Nasr Supplies', skipOffstage: false), findsOneWidget);
    // MoneyRow renders a proper minus sign (U+2212) with the currency shown
    // separately.
    expect(find.textContaining('−45,000', skipOffstage: false), findsOneWidget);

    // Contract Value is demoted to a compact, muted secondary row (per the
    // v2 UI audit) — guard against it being re-inflated back to prominent
    // styling.
    final contractValueRow = find.byKey(
      const Key('qa_dashboard_project_contract_value'),
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

    // Profit Margin KPI (v2 UI audit Task B4): 84,500 / 220,000 * 100 =
    // 38.4%, shown as its own stat tile next to the Net Profit hero.
    expect(
      find.byKey(
        const Key('qa_dashboard_project_profit_margin'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('38.4%', skipOffstage: false), findsOneWidget);
    final marginDy = tester
        .getTopLeft(
          find.byKey(
            const Key('qa_dashboard_project_profit_margin'),
            skipOffstage: false,
          ),
        )
        .dy;
    expect(marginDy, greaterThan(heroDy));
  });

  testWidgets('project selector can switch back to All Projects', (
    tester,
  ) async {
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
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
        selectedDashboardProjectIdProvider.overrideWith((ref) => 'project_1'),
        dashboardSnapshotProvider.overrideWith(
          (ref, workspaceId) =>
              Stream.value(DashboardSnapshot.fromMap({'totalExpenses': 1000})),
        ),
        dashboardPreviousWeekSummaryProvider.overrideWith(
          (ref, workspaceId) => Stream.value(const <String, num>{}),
        ),
        projectsProvider.overrideWith(
          (ref) => Stream.value(const <Project>[project]),
        ),
        projectRecentTransactionsProvider.overrideWith(
          (ref, scope) => Stream.value(const <DashboardTransactionRef>[]),
        ),
        notificationItemsProvider.overrideWith((ref) => Stream.value(const [])),
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(selectedDashboardProjectIdProvider), 'project_1');

    // Open selector and choose "All Projects" — must clear the selection
    // (regression: null PopupMenuButton value was swallowed as a cancel).
    await tester.tap(find.byKey(const Key('qa_dashboard_project_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Projects').last);
    await tester.pumpAndSettle();

    expect(container.read(selectedDashboardProjectIdProvider), isNull);
  });
}
