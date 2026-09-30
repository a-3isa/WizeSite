import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/data/report_project_selector_provider.dart';
import 'package:buildtrack_app/features/reports/domain/report_scope.dart';
import 'package:buildtrack_app/features/reports/presentation/screens/reports_screen.dart';
import 'package:buildtrack_app/features/reports/services/report_export_data_builder.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CancellableExportBuilder implements ReportExportDataBuilder {
  @override
  Future<ReportExportData> build({
    required String workspaceId,
    required String projectId,
    required DateTime startDate,
    required DateTime endDate,
    required bool includeExpenses,
    required bool includePayments,
    required bool includeEntities,
    required bool includeDaily,
    required bool includeWeekly,
    ReportExportProgressCallback? onProgress,
    ReportExportCancellationCheck? isCancelled,
  }) async {
    onProgress?.call(
      const ReportExportProgress(
        stage: ReportExportStage.expenses,
        loadedRecords: 42,
      ),
    );
    while (isCancelled?.call() != true) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw const ReportExportCancelled();
  }
}

void main() {
  testWidgets('reports header does not overflow on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpReportsScreen(tester, role: AccountingAccessRoleType.owner);

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  for (final role in [
    AccountingAccessRoleType.owner,
    AccountingAccessRoleType.admin,
    AccountingAccessRoleType.accountingApproved,
  ]) {
    testWidgets('reports screen allows ${role.value} exports', (tester) async {
      await _pumpReportsScreen(tester, role: role);
      await tester.pumpAndSettle();

      expect(find.text('Exports'), findsOneWidget);
      await tester.tap(find.text('Exports'));
      await tester.pumpAndSettle();
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Export weekly report'), findsOneWidget);
      expect(find.text('Build custom report'), findsOneWidget);
      expect(find.text('Total Expenses'), findsOneWidget);
      expect(find.textContaining('permission'), findsNothing);
    });
  }

  testWidgets('expense-ledger reports omit income and net cards', (
    tester,
  ) async {
    await _pumpReportsScreen(
      tester,
      role: AccountingAccessRoleType.owner,
      project: const Project(
        id: 'project_1',
        workspaceId: 'workspace_1',
        name: 'Expense Only',
        clientName: 'Client',
        contractValue: null,
        status: 'active',
        completionPercentage: 10,
        totalExpenses: 100,
        totalPayments: 0,
        netProfit: -100,
        isArchived: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Expenses'), findsAtLeastNWidgets(1));
    expect(find.text('Total Income'), findsNothing);
    expect(find.text('Net Profit'), findsNothing);
  });

  testWidgets('reports screen denies member access to financial reports', (
    tester,
  ) async {
    await _pumpReportsScreen(tester, role: AccountingAccessRoleType.member);
    await tester.pumpAndSettle();

    expect(find.text('Exports'), findsNothing);
    expect(find.text('Total Expenses'), findsNothing);
    expect(
      find.textContaining('permission to view financial reports'),
      findsOneWidget,
    );
  });

  testWidgets('reports screen denies access when membership is missing', (
    tester,
  ) async {
    await _pumpReportsScreen(tester, role: null);
    await tester.pumpAndSettle();

    expect(find.text('Exports'), findsNothing);
    expect(find.text('Total Expenses'), findsNothing);
    expect(
      find.textContaining('permission to view financial reports'),
      findsOneWidget,
    );
  });

  testWidgets('reports screen exposes the shared month-to-date scope', (
    tester,
  ) async {
    await _pumpReportsScreen(tester, role: AccountingAccessRoleType.owner);
    await tester.pumpAndSettle();

    expect(find.text('From: 2026-06-01'), findsOneWidget);
    expect(find.text('To: 2026-06-15'), findsOneWidget);
  });

  testWidgets('report selector can switch to archived project pages', (
    tester,
  ) async {
    await _pumpReportsScreen(tester, role: AccountingAccessRoleType.owner);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show archived projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();

    expect(find.text('Archived Tower'), findsOneWidget);
  });

  testWidgets('empty charts stay friendly and populated charts can be shared', (
    tester,
  ) async {
    await _pumpReportsScreen(tester, role: AccountingAccessRoleType.owner);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('No data yet'), findsNWidgets(3));
    expect(find.byTooltip('Share chart'), findsNothing);

    await _pumpReportsScreen(
      tester,
      role: AccountingAccessRoleType.owner,
      metrics: ReportMetrics(
        projectId: 'project_1',
        projectName: 'Tower A',
        status: 'active',
        isArchived: false,
        totalExpenses: 100,
        totalIncome: 200,
        net: 100,
        categoryTotals: const {'materials': 100},
        monthlyFlow: [
          MonthlyFlowData(
            month: DateTime.utc(2026, 6),
            expenses: 100,
            income: 200,
          ),
        ],
        topWorkers: const [],
        recentExpenses: const [],
        recentPayments: const [],
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Share chart'), findsAtLeastNWidgets(1));
  });

  testWidgets('custom export shows progress and can be cancelled', (
    tester,
  ) async {
    await _pumpReportsScreen(
      tester,
      role: AccountingAccessRoleType.owner,
      exportDataBuilder: _CancellableExportBuilder(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build custom report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export PDF').last);
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.text('Loaded 42 records'), findsOneWidget);
    expect(find.text('Cancel export'), findsOneWidget);
    await tester.tap(find.text('Cancel export'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Loaded 42 records'), findsNothing);
  });
}

Future<void> _pumpReportsScreen(
  WidgetTester tester, {
  required AccountingAccessRoleType? role,
  ReportMetrics? metrics,
  ReportExportDataBuilder? exportDataBuilder,
  Project? project,
}) {
  final activeProject = project ??
      const Project(
        id: 'project_1',
        workspaceId: 'workspace_1',
        name: 'Tower A',
        clientName: 'Client',
        contractValue: 1000,
        status: 'active',
        completionPercentage: 10,
        totalExpenses: 100,
        totalPayments: 200,
        netProfit: 100,
        isArchived: false,
      );
  final archivedProject = const Project(
    id: 'project_archived',
    workspaceId: 'workspace_1',
    name: 'Archived Tower',
    clientName: 'Old Client',
    contractValue: 800,
    status: 'completed',
    completionPercentage: 100,
    totalExpenses: 500,
    totalPayments: 800,
    netProfit: 300,
    isArchived: true,
  );
  final selector = ReportProjectSelectorController(
    loadActivePage: ({cursor}) async =>
        FirestorePage(items: [activeProject], hasMore: false),
    loadArchivedPage: ({cursor}) async =>
        FirestorePage(items: [archivedProject], hasMore: false),
  );
  return selector.loadInitial().then((_) {
    return tester.pumpWidget(
      ProviderScope(
        key: ValueKey<Object?>(metrics ?? exportDataBuilder ?? role),
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          currentAccountingRoleProvider.overrideWith(
            (ref) => Stream.value(role),
          ),
          projectsProvider.overrideWith((ref) => Stream.value([activeProject])),
          reportProjectSelectorProvider.overrideWith((ref) => selector),
          reportProjectIdProvider.overrideWith((ref) => 'project_1'),
          reportScopeProvider.overrideWith(
            (ref) => ReportScope.monthToDate(
              projectId: 'project_1',
              now: DateTime(2026, 6, 15),
            ),
          ),
          reportMetricsProvider.overrideWith(
            (ref) => AsyncData(
              metrics ??
                  const ReportMetrics(
                    projectId: 'project_1',
                    projectName: 'Tower A',
                    status: 'active',
                    isArchived: false,
                    totalExpenses: 100,
                    totalIncome: 200,
                    net: 100,
                    categoryTotals: {},
                    monthlyFlow: [],
                    topWorkers: [],
                    recentExpenses: [],
                    recentPayments: [],
                  ),
            ),
          ),
          currentUsageProvider.overrideWith(
            (ref) =>
                Stream.value(UsageSnapshot.empty(limits: PlanLimits.free())),
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
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReportsScreen(
            projectId: 'project_1',
            exportDataBuilder: exportDataBuilder,
          ),
        ),
      ),
    );
  });
}
