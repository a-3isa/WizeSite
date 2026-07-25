import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/widgets/resource_directory_links.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for the shared resource-directory hub (now on the More tab, not the
/// Home dashboard). Consolidates the assertions that previously lived in
/// dashboard_screen_test.dart (live workers count + Workers prominence) and
/// accessibility_rtl_test.dart (button semantics + 48dp touch targets), tied to
/// the widget itself so they hold wherever it's hosted.
void main() {
  Widget host({required List<WorkerProfile> workers}) => ProviderScope(
    overrides: [workersProvider.overrideWith((ref) => Stream.value(workers))],
    child: const MaterialApp(
      localizationsDelegates: [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ResourceDirectoryLinks()),
    ),
  );

  List<WorkerProfile> makeWorkers(int n) => List.generate(
    n,
    (i) => WorkerProfile(
      id: 'worker_$i',
      workspaceId: 'workspace_1',
      name: 'Worker $i',
      phoneNumber: '0100000000$i',
      dailyWage: 100,
      billingType: 'daily',
      workerType: 'general',
      notes: '',
      isArchived: false,
    ),
  );

  testWidgets('shows a live workers count and all four resource links', (
    tester,
  ) async {
    await tester.pumpWidget(host(workers: makeWorkers(26)));
    await tester.pumpAndSettle();

    expect(find.text('Workers (26)'), findsOneWidget);
    expect(find.text('Contractors'), findsOneWidget);
    expect(find.text('Equipment providers'), findsOneWidget);
    expect(find.text('Transport providers'), findsOneWidget);
    for (final key in [
      'qa_resource_workers',
      'qa_resource_contractors',
      'qa_resource_equipment',
      'qa_resource_transport',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
  });

  testWidgets('Workers is visually prominent: first and larger', (
    tester,
  ) async {
    await tester.pumpWidget(host(workers: makeWorkers(26)));
    await tester.pumpAndSettle();

    final workersDy = tester
        .getTopLeft(find.byKey(const Key('qa_resource_workers')))
        .dy;
    final contractorsDy = tester
        .getTopLeft(find.byKey(const Key('qa_resource_contractors')))
        .dy;
    expect(workersDy, lessThan(contractorsDy));

    final workersFont = tester.widget<Text>(find.text('Workers (26)')).style;
    final contractorsFont = tester.widget<Text>(find.text('Contractors')).style;
    expect(workersFont!.fontSize, greaterThan(contractorsFont!.fontSize!));
  });

  testWidgets('every resource card exposes button semantics', (tester) async {
    await tester.pumpWidget(host(workers: makeWorkers(26)));
    await tester.pumpAndSettle();

    for (final label in [
      'Workers (26)',
      'Contractors',
      'Equipment providers',
      'Transport providers',
    ]) {
      final matches = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((w) => w.properties.label == label)
          .toList();
      expect(matches, hasLength(1), reason: 'semantics for "$label"');
      expect(matches.single.properties.button, isTrue);
    }
  });

  testWidgets('every resource card meets the 48dp touch-target minimum', (
    tester,
  ) async {
    await tester.pumpWidget(host(workers: makeWorkers(3)));
    await tester.pumpAndSettle();

    for (final key in [
      'qa_resource_workers',
      'qa_resource_contractors',
      'qa_resource_equipment',
      'qa_resource_transport',
    ]) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(48),
        reason: '$key should meet the 48dp minimum touch target',
      );
    }
  });
}
