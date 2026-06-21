import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/widgets/active_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('renders nothing when there are no active filters', (
    tester,
  ) async {
    await _pump(tester, ActiveFilterBar(filters: const [], onRemove: (_) {}));

    expect(find.byType(FilterToken), findsNothing);
    expect(find.text('Active filters'), findsNothing);
  });

  testWidgets('renders one removable token per active filter', (tester) async {
    await _pump(
      tester,
      ActiveFilterBar(
        filters: const [
          ActiveFilter(id: 'category', label: 'Labor'),
          ActiveFilter(id: 'project', label: 'Tower A'),
        ],
        onRemove: (_) {},
      ),
    );

    expect(find.byType(FilterToken), findsNWidgets(2));
    expect(find.text('Labor'), findsOneWidget);
    expect(find.text('Tower A'), findsOneWidget);
  });

  testWidgets('removing a token reports its id', (tester) async {
    String? removed;
    await _pump(
      tester,
      ActiveFilterBar(
        filters: const [
          ActiveFilter(id: 'category', label: 'Labor'),
          ActiveFilter(id: 'project', label: 'Tower A'),
        ],
        onRemove: (id) => removed = id,
      ),
    );

    // The remove affordance carries a localized tooltip/semantics label.
    await tester.tap(find.byTooltip('Remove filter').first);
    await tester.pump();

    expect(removed, 'category');
  });

  testWidgets('shows a clear-all action only with multiple filters', (
    tester,
  ) async {
    var cleared = 0;
    await _pump(
      tester,
      ActiveFilterBar(
        filters: const [
          ActiveFilter(id: 'a', label: 'A'),
          ActiveFilter(id: 'b', label: 'B'),
        ],
        onRemove: (_) {},
        onClearAll: () => cleared++,
      ),
    );

    final clearAll = find.text('Clear all filters');
    expect(clearAll, findsOneWidget);

    await tester.tap(clearAll);
    await tester.pump();
    expect(cleared, 1);
  });

  testWidgets('hides clear-all with a single filter', (tester) async {
    await _pump(
      tester,
      ActiveFilterBar(
        filters: const [ActiveFilter(id: 'a', label: 'A')],
        onRemove: (_) {},
        onClearAll: () {},
      ),
    );

    expect(find.text('Clear all filters'), findsNothing);
  });
}
