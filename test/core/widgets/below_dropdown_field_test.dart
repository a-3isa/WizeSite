import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BelowDropdownField opens its menu below the field', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: 80, left: 16, right: 16),
            child: BelowDropdownField<String>(
              label: 'Project',
              value: 'one',
              entries: const [
                DropdownMenuEntry(value: 'one', label: 'Project one'),
                DropdownMenuEntry(value: 'two', label: 'Project two'),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final fieldTop = tester.getTopLeft(find.byType(BelowDropdownField<String>));
    final fieldBottom = tester.getBottomLeft(
      find.byType(BelowDropdownField<String>),
    );

    await tester.tap(find.byType(BelowDropdownField<String>));
    await tester.pumpAndSettle();

    final itemTop = tester.getTopLeft(find.text('Project two').last);

    expect(fieldTop.dy, lessThan(fieldBottom.dy));
    expect(itemTop.dy, greaterThanOrEqualTo(fieldBottom.dy - 1));
  });
}
