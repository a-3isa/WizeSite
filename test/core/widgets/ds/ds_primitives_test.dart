import 'package:buildtrack_app/app/theme/app_theme.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(const Locale('en')),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('BuildButton renders its label and fires onPressed', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(BuildButton(label: 'Save', onPressed: () => tapped = true)),
    );
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    expect(tapped, isTrue);
  });

  testWidgets('MoneyRow shows a signed income amount', (tester) async {
    await tester.pumpWidget(
      _host(
        const MoneyRow(
          title: 'Owner deposit',
          amount: '120,000',
          kind: MoneyKind.income,
          showDivider: false,
        ),
      ),
    );
    expect(find.text('+120,000'), findsOneWidget);
    expect(find.text('Owner deposit'), findsOneWidget);
  });

  testWidgets('MoneyRow shows a signed expense amount', (tester) async {
    await tester.pumpWidget(
      _host(
        const MoneyRow(
          title: 'Steel',
          amount: '4,500',
          showDivider: false,
        ),
      ),
    );
    expect(find.text('−4,500'), findsOneWidget);
  });

  testWidgets('SegmentedToggle reports selection changes', (tester) async {
    var value = 'a';
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => SegmentedToggle<String>(
            value: value,
            onChanged: (v) => setState(() => value = v),
            options: const [
              SegmentedOption(value: 'a', label: 'A'),
              SegmentedOption(value: 'b', label: 'B'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(value, 'b');
  });

  testWidgets('Avatar derives initials', (tester) async {
    await tester.pumpWidget(_host(const Avatar(label: 'Eng Ahmed')));
    expect(find.text('EA'), findsOneWidget);
  });
}
