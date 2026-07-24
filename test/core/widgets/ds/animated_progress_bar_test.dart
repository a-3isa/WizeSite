import 'package:buildtrack_app/app/theme/app_theme.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(const Locale('en')),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AnimatedProgressBar', () {
    testWidgets('fills in from zero to its target fraction', (tester) async {
      await tester.pumpWidget(
        _host(
          const AnimatedProgressBar(
            value: 0.75,
            color: Colors.green,
            backgroundColor: Colors.grey,
            duration: Duration(milliseconds: 300),
          ),
        ),
      );

      var indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, 0.0);

      await tester.pump(const Duration(milliseconds: 300));
      indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(0.75, 0.001));
    });

    testWidgets('clamps out-of-range values into [0, 1]', (tester) async {
      await tester.pumpWidget(
        _host(
          const AnimatedProgressBar(
            value: 1.4,
            color: Colors.red,
            backgroundColor: Colors.grey,
            duration: Duration(milliseconds: 200),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, 1.0);
    });

    testWidgets(
      'reduced motion (accessibility) renders the target fraction immediately',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(const Locale('en')),
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: const Scaffold(
                body: AnimatedProgressBar(
                  value: 0.6,
                  color: Colors.blue,
                  backgroundColor: Colors.grey,
                ),
              ),
            ),
          ),
        );

        final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(indicator.value, 0.6);
      },
    );
  });
}
