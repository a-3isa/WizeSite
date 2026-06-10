import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/presentation/screens/reports_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Export weekly report'), findsOneWidget);
      expect(find.text('Build custom report'), findsOneWidget);
      expect(find.text('Total Expenses'), findsOneWidget);
      expect(find.textContaining('permission'), findsNothing);
    });
  }

  testWidgets('reports screen denies member access to financial reports', (
    tester,
  ) async {
    await _pumpReportsScreen(tester, role: AccountingAccessRoleType.member);
    await tester.pumpAndSettle();

    expect(find.text('Export PDF'), findsNothing);
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

    expect(find.text('Export PDF'), findsNothing);
    expect(find.text('Total Expenses'), findsNothing);
    expect(
      find.textContaining('permission to view financial reports'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpReportsScreen(
  WidgetTester tester, {
  required AccountingAccessRoleType? role,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
        activeUserIdProvider.overrideWith((ref) => 'user_1'),
        currentAccountingRoleProvider.overrideWith((ref) => Stream.value(role)),
        projectsProvider.overrideWith(
          (ref) => Stream.value([
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
            ),
          ]),
        ),
        reportProjectIdProvider.overrideWith((ref) => 'project_1'),
        reportMetricsProvider.overrideWith(
          (ref) => const AsyncData(
            ReportMetrics(
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
    ),
  );
}
