import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
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
}
