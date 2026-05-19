import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/session_restore_service.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockSessionRestoreService extends Mock
    implements SessionRestoreService {}

GoRouter _router() {
  return GoRouter(
    initialLocation: AppRoutes.root,
    routes: [
      GoRoute(
        path: AppRoutes.root,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.features,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Features Screen'))),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Dashboard Screen'))),
      ),
    ],
  );
}

Widget _testApp(SessionRestoreService sessionRestoreService) {
  return ProviderScope(
    overrides: [
      sessionRestoreServiceProvider.overrideWithValue(sessionRestoreService),
    ],
    child: MaterialApp.router(
      routerConfig: _router(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  testWidgets('SplashScreen routes signed-out restore miss to features', (
    tester,
  ) async {
    final sessionRestoreService = _MockSessionRestoreService();
    when(() => sessionRestoreService.restore()).thenAnswer((_) async => null);

    await tester.pumpWidget(_testApp(sessionRestoreService));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(find.text('Features Screen'), findsOneWidget);
  });

  testWidgets(
    'SplashScreen restores workspace context and routes to dashboard',
    (tester) async {
      final sessionRestoreService = _MockSessionRestoreService();
      when(() => sessionRestoreService.restore()).thenAnswer(
        (_) async => const SessionRestoreResult(
          userId: 'user_1',
          workspaceId: 'workspace_1',
        ),
      );

      await tester.pumpWidget(_testApp(sessionRestoreService));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Screen'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.text('Dashboard Screen')),
        listen: false,
      );
      expect(container.read(activeUserIdProvider), 'user_1');
      expect(container.read(activeWorkspaceIdProvider), 'workspace_1');
    },
  );
}
