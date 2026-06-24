import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/initial_workspace_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  Future<void> pumpSetup(
    WidgetTester tester, {
    required WorkspaceMutationService workspaceService,
  }) async {
    final router = GoRouter(
      initialLocation: AppRoutes.initialWorkspaceSetup,
      routes: [
        GoRoute(
          path: AppRoutes.initialWorkspaceSetup,
          builder: (context, state) => const InitialWorkspaceSetupScreen(),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (context, state) =>
              const Text('Dashboard', textDirection: TextDirection.ltr),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          workspaceMutationServiceProvider.overrideWithValue(workspaceService),
        ],
        child: MaterialApp.router(
          routerConfig: router,
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
  }

  testWidgets('requires workspace name before saving setup', (tester) async {
    final workspaceService = _MockWorkspaceMutationService();

    await pumpSetup(tester, workspaceService: workspaceService);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a workspace name.'), findsOneWidget);
    verifyNever(
      () => workspaceService.completeInitialWorkspaceSetup(
        workspaceId: any(named: 'workspaceId'),
        workspaceName: any(named: 'workspaceName'),
        defaultCurrency: any(named: 'defaultCurrency'),
      ),
    );
  });

  testWidgets('saves setup and routes to dashboard', (tester) async {
    final workspaceService = _MockWorkspaceMutationService();
    when(
      () => workspaceService.completeInitialWorkspaceSetup(
        workspaceId: 'workspace_1',
        workspaceName: 'Acme Sites',
        defaultCurrency: 'SAR',
      ),
    ).thenAnswer(
      (_) async => const WorkspaceBootstrapResult(
        workspaceId: 'workspace_1',
        created: false,
        setupCompleted: true,
      ),
    );

    await pumpSetup(tester, workspaceService: workspaceService);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace name'),
      'Acme Sites',
    );
    await tester.tap(find.text('EGP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAR').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    verify(
      () => workspaceService.completeInitialWorkspaceSetup(
        workspaceId: 'workspace_1',
        workspaceName: 'Acme Sites',
        defaultCurrency: 'SAR',
      ),
    ).called(1);
    expect(find.text('Dashboard'), findsOneWidget);
  });
}
