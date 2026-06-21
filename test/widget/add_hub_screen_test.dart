import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/features/add/presentation/screens/add_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Observer extends NavigatorObserver {
  int pushed = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) pushed += 1;
  }
}

void main() {
  testWidgets('Add hub exposes action parity with localized semantics', (
    tester,
  ) async {
    final observer = _Observer();
    final blocker = Completer<void>();
    final router = GoRouter(
      initialLocation: AppRoutes.add,
      observers: [observer],
      routes: [
        GoRoute(path: AppRoutes.add, builder: (_, _) => const AddHubScreen()),
        for (final path in const [
          AppRoutes.addExpense,
          AppRoutes.addPayment,
          AppRoutes.addWorker,
          AppRoutes.voiceExpense,
          AppRoutes.workers,
          AppRoutes.contractorsDirectory,
          AppRoutes.equipmentDirectory,
          AppRoutes.transportProvidersDirectory,
        ])
          GoRoute(path: path, builder: (_, _) => Text(path)),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPrefetcherProvider.overrideWithValue(
            AppPrefetcher(
              warm: ({required target, projectId}) => blocker.future,
            ),
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

    expect(find.byKey(const Key('qa_add_hub_expense')), findsOneWidget);
    expect(find.byKey(const Key('qa_add_hub_payment')), findsOneWidget);
    expect(find.byKey(const Key('qa_add_hub_worker_entry')), findsOneWidget);
    expect(find.bySemanticsLabel('Add Expense'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa_add_hub_expense')));
    await tester.tap(find.byKey(const Key('qa_add_hub_expense')));
    await tester.pump();
    expect(observer.pushed, 1);

    router.go(AppRoutes.add);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('qa_add_hub_voice_expense')),
      240,
    );
    expect(find.byKey(const Key('qa_add_hub_voice_expense')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('qa_add_hub_contractors_directory')),
      240,
    );
    expect(find.text('Resources'), findsOneWidget);
    expect(
      find.byKey(const Key('qa_add_hub_workers_directory')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('qa_add_hub_contractors_directory')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('qa_add_hub_equipment_directory')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('qa_add_hub_transport_directory')),
      findsOneWidget,
    );
  });
}
