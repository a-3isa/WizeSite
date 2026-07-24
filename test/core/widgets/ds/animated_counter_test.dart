import 'package:buildtrack_app/app/theme/app_theme.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(const Locale('en')),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AnimatedCounter', () {
    testWidgets('counts up from zero to the formatted target', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AnimatedCounter(
            '84,500',
            duration: Duration(milliseconds: 400),
          ),
        ),
      );

      // First frame: the tween starts at 0.
      expect(find.text('0'), findsOneWidget);
      expect(find.text('84,500'), findsNothing);

      // Advancing past the animation duration settles on the caller's
      // verbatim target string.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('84,500'), findsOneWidget);
    });

    testWidgets('animates a negative (loss) figure and settles with its sign', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AnimatedCounter(
            '−45,000',
            duration: Duration(milliseconds: 400),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('−45,000'), findsOneWidget);
    });

    testWidgets('animates a decimal percentage and settles on the exact text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AnimatedCounter('38.4%', duration: Duration(milliseconds: 300)),
        ),
      );

      expect(find.text('0.0%'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('38.4%'), findsOneWidget);
    });

    testWidgets(
      'settles on the exact original text for Arabic-Indic digit strings',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const AnimatedCounter(
              '١٬٢٣٤٫٥٠ EGP',
              duration: Duration(milliseconds: 300),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('١٬٢٣٤٫٥٠ EGP'), findsOneWidget);
      },
    );

    testWidgets('renders a non-numeric placeholder as-is, unanimated', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AnimatedCounter('—')));
      expect(find.text('—'), findsOneWidget);

      // Nothing to animate -- no extra pump should change anything.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets(
      'reduced motion (accessibility) shows the target immediately',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(const Locale('en')),
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: const Scaffold(
                body: Center(
                  child: AnimatedCounter(
                    '84,500',
                    duration: Duration(milliseconds: 400),
                  ),
                ),
              ),
            ),
          ),
        );

        // No pump needed -- reduced motion skips straight to the target.
        expect(find.text('84,500'), findsOneWidget);
      },
    );
  });
}
