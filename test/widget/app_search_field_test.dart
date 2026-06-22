import 'package:buildtrack_app/core/widgets/app_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a clear action and reports cleared search text', (
    tester,
  ) async {
    final controller = TextEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSearchField(
            controller: controller,
            labelText: 'Search',
            clearButtonKey: const Key('clear_search'),
            onChanged: changes.add,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('clear_search')), findsNothing);

    await tester.enterText(find.byType(TextField), 'concrete');
    await tester.pump();

    expect(find.byKey(const Key('clear_search')), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear_search')));
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(changes.last, isEmpty);
    expect(find.byKey(const Key('clear_search')), findsNothing);
  });
}
