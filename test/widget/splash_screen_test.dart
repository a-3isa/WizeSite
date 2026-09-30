import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/app_remote_config.dart';
import 'package:buildtrack_app/core/services/session_restore_service.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
      GoRoute(
        path: AppRoutes.initialWorkspaceSetup,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Workspace Setup'))),
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
  AppRemoteConfig? remoteConfig,
}) {
  return ProviderScope(
    overrides: [
      sessionRestoreServiceProvider.overrideWithValue(sessionRestoreService),
      if (prefetcher != null)
        appPrefetcherProvider.overrideWithValue(prefetcher),
      if (remoteConfig != null)
        appRemoteConfigProvider.overrideWith((ref) async => remoteConfig),
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
          setupCompleted: true,
        ),
      );

      await tester.pumpWidget(
        _testApp(sessionRestoreService, prefetcher: _instantPrefetcher()),
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

  testWidgets('SplashScreen does not block dashboard on warmCritical', (
    tester,
  ) async {
    final sessionRestoreService = _MockSessionRestoreService();
    when(() => sessionRestoreService.restore()).thenAnswer(
      (_) async => const SessionRestoreResult(
        userId: 'user_1',
        workspaceId: 'workspace_1',
        setupCompleted: true,
      ),
    );

    await tester.pumpWidget(
      _testApp(sessionRestoreService, prefetcher: _blockingPrefetcher()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Dashboard Screen'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Drain the old warmCritical timeout if this regresses, so the test
    // framework does not report leaked timers after the assertion.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('SplashScreen routes incomplete first-time users to setup', (
    tester,
  ) async {
    final sessionRestoreService = _MockSessionRestoreService();
    when(() => sessionRestoreService.restore()).thenAnswer(
      (_) async => const SessionRestoreResult(
        userId: 'user_1',
        workspaceId: 'workspace_1',
        setupCompleted: false,
      ),
    );

    await tester.pumpWidget(
      _testApp(sessionRestoreService, prefetcher: _instantPrefetcher()),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('Workspace Setup'), findsOneWidget);
    expect(find.text('Dashboard Screen'), findsNothing);
  });

  testWidgets(
    'SplashScreen does NOT show progress bar before session is restored',
    (tester) async {
      final restoreCompleter = Completer<SessionRestoreResult?>();
      final sessionRestoreService = _MockSessionRestoreService();
      when(
        () => sessionRestoreService.restore(),
      ).thenAnswer((_) => restoreCompleter.future);

      await tester.pumpWidget(
        _testApp(sessionRestoreService, prefetcher: _instantPrefetcher()),
      );
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'SplashScreen blocks on update-required when build is below the minimum',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'WizeSite',
        packageName: 'com.ahmed.buildozer',
        version: '1.0.0',
        buildNumber: '5',
        buildSignature: '',
      );
      final sessionRestoreService = _MockSessionRestoreService();

      await tester.pumpWidget(
        _testApp(
          sessionRestoreService,
          remoteConfig: const AppRemoteConfig(minSupportedBuild: 10),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Features Screen'), findsNothing);
      verifyNever(() => sessionRestoreService.restore());
    },
  );
}
