import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
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

/// Creates an [AppPrefetcher] whose [warmCritical] completes immediately.
AppPrefetcher _instantPrefetcher() {
  return AppPrefetcher(
    warm: ({required target, projectId}) => Future<void>.value(),
  );
}

/// Creates an [AppPrefetcher] whose [warmCritical] never completes
/// (useful for testing the in-progress state).
AppPrefetcher _blockingPrefetcher() {
  return AppPrefetcher(
    warm: ({required target, projectId}) => Completer<void>().future,
  );
}

Widget _testApp(
  SessionRestoreService sessionRestoreService, {
  AppPrefetcher? prefetcher,
}) {
  return ProviderScope(
    overrides: [
      sessionRestoreServiceProvider.overrideWithValue(sessionRestoreService),
      if (prefetcher != null)
        appPrefetcherProvider.overrideWithValue(prefetcher),
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
    // min display delay is 800 ms; pump past it
    await tester.pump(const Duration(milliseconds: 900));
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

      await tester.pumpWidget(
        _testApp(
          sessionRestoreService,
          prefetcher: _instantPrefetcher(),
        ),
      );
      // warmCritical instant + 800 ms min delay
      await tester.pump(const Duration(milliseconds: 900));
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

  testWidgets(
    'SplashScreen shows LinearProgressIndicator while warmCritical is pending',
    (tester) async {
      final sessionRestoreService = _MockSessionRestoreService();
      when(() => sessionRestoreService.restore()).thenAnswer(
        (_) async => const SessionRestoreResult(
          userId: 'user_1',
          workspaceId: 'workspace_1',
        ),
      );

      await tester.pumpWidget(
        _testApp(
          sessionRestoreService,
          prefetcher: _blockingPrefetcher(),
        ),
      );
      // Let session restore complete and setState(_showProgress) run
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // Not yet navigated
      expect(find.text('Dashboard Screen'), findsNothing);

      // Drain pending timers (5 s warmCritical timeout + 800 ms min delay)
      // so the test framework does not flag them as leaked.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'SplashScreen does NOT show progress bar before session is restored',
    (tester) async {
      final restoreCompleter = Completer<SessionRestoreResult?>();
      final sessionRestoreService = _MockSessionRestoreService();
      when(() => sessionRestoreService.restore())
          .thenAnswer((_) => restoreCompleter.future);

      await tester.pumpWidget(
        _testApp(sessionRestoreService, prefetcher: _instantPrefetcher()),
      );
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );
}
