import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/app_theme.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/activity/presentation/screens/activity_screen.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DashboardWeeklyInsights _insights() => DashboardWeeklyInsights(
  topEntity: '',
  topCategory: '',
  laborTotal: 0,
  equipmentTotal: 0,
  paymentSummary: const {},
  recentTransactions: [
    WeeklyDashboardTransaction(
      title: 'Owner deposit',
      amount: 120000,
      date: DateTime(2026, 6, 30),
      type: 'payment',
    ),
    WeeklyDashboardTransaction(
      title: 'Steel supplier',
      amount: 4500,
      date: DateTime(2026, 6, 29),
      type: 'expense',
    ),
  ],
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeWorkspaceIdProvider.overrideWith((ref) => 'ws1'),
        dashboardWeeklyInsightsProvider(
          'ws1',
        ).overrideWith((ref) => Stream.value(_insights())),
      ],
      child: MaterialApp(
        theme: AppTheme.light(const Locale('en')),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ActivityScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows all transactions by default', (tester) async {
    await _pump(tester);
    expect(find.text('Owner deposit'), findsOneWidget);
    expect(find.text('Steel supplier'), findsOneWidget);
  });

  testWidgets('Income filter hides expenses', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(find.text('Owner deposit'), findsOneWidget);
    expect(find.text('Steel supplier'), findsNothing);
  });

  testWidgets('Expenses filter hides income', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    expect(find.text('Steel supplier'), findsOneWidget);
    expect(find.text('Owner deposit'), findsNothing);
  });
}
