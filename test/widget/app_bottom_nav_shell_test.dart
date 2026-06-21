import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/widgets/app_bottom_nav_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router() {
  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AppBottomNavShell(navigationShell: shell),
        branches: [
          for (final route in const [
            AppRoutes.dashboard,
            AppRoutes.add,
            AppRoutes.reports,
            AppRoutes.projects,
          ])
            StatefulShellBranch(
              routes: [
                GoRoute(path: route, builder: (context, state) => Text(route)),
              ],
            ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('shell exposes four stable reachable destinations', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          appPrefetcherProvider.overrideWithValue(
            AppPrefetcher(warm: ({required target, projectId}) {}),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final entry in const {
      'Add': AppRoutes.add,
      'Reports': AppRoutes.reports,
      'Projects': AppRoutes.projects,
      'Home': AppRoutes.dashboard,
    }.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, entry.value);
    }

    await tester.tap(find.text('Home'));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.dashboard);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.dashboard);
  });

  testWidgets('offline banner animates without moving shell content', (
    tester,
  ) async {
    final connectivity = StreamController<bool>();
    addTearDown(connectivity.close);
    final router = _router();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityProvider.overrideWith((ref) => connectivity.stream),
          appPrefetcherProvider.overrideWithValue(
            AppPrefetcher(warm: ({required target, projectId}) {}),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );

    connectivity.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final onlineTop = tester.getTopLeft(find.text(AppRoutes.dashboard)).dy;

    connectivity.add(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.byKey(const Key('offline_banner_overlay')), findsOneWidget);
    expect(tester.getTopLeft(find.text(AppRoutes.dashboard)).dy, onlineTop);

    connectivity.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.getTopLeft(find.text(AppRoutes.dashboard)).dy, onlineTop);
  });
}
