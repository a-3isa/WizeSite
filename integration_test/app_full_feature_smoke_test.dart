import 'package:buildtrack_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real device app starts and reaches an interactive route', (
    tester,
  ) async {
    await app.main();
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(MaterialApp), findsOneWidget);

    final interactiveTargets = find.byWidgetPredicate((widget) {
      return widget is IconButton ||
          widget is FilledButton ||
          widget is TextButton ||
          widget is NavigationBar ||
          widget is InkWell;
    });
    expect(interactiveTargets, findsWidgets);

    Future<void> tapIfPresent(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        return;
      }
      await tester.tap(finder.first);
      await tester.pump(const Duration(seconds: 1));
    }

    await tapIfPresent(find.byKey(const Key('qa_dashboard_settings')));
    if (find.byKey(const Key('qa_dashboard_settings')).evaluate().isEmpty) {
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
    }

    await tapIfPresent(find.byKey(const Key('qa_nav_add')));
    await tapIfPresent(find.byKey(const Key('qa_add_hub_expense')));
    if (find.byKey(const Key('qa_add_hub_expense')).evaluate().isEmpty) {
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
    }

    await tapIfPresent(find.byKey(const Key('qa_nav_projects')));
    await tapIfPresent(find.byKey(const Key('qa_nav_home')));
  });
}
