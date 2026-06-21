import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
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
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('AppLoadingSkeleton', () {
    testWidgets('renders skeleton bars with a localized semantics label', (
      tester,
    ) async {
      await _pump(tester, const AppLoadingSkeleton(lineCount: 4));

      expect(find.byType(AppLoadingSkeleton), findsOneWidget);
      // Default accessible label comes from the loadingContent key.
      expect(find.bySemanticsLabel('Loading content'), findsOneWidget);
    });

    testWidgets('honors a custom semantics label', (tester) async {
      await _pump(
        tester,
        const AppLoadingSkeleton(semanticsLabel: 'Loading reports'),
      );

      expect(find.bySemanticsLabel('Loading reports'), findsOneWidget);
    });
  });

  group('AppRecoverableError', () {
    testWidgets('shows the sanitized message and default title', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppRecoverableError(message: 'We could not load this.'),
      );

      expect(find.text('We could not load this.'), findsOneWidget);
      expect(find.text('We hit a snag'), findsOneWidget);
    });

    testWidgets('renders a retry CTA only when onRetry is provided', (
      tester,
    ) async {
      var retried = 0;
      await _pump(
        tester,
        AppRecoverableError(message: 'Network error', onRetry: () => retried++),
      );

      final retry = find.widgetWithText(ElevatedButton, 'Try again');
      expect(retry, findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('omits the retry CTA when onRetry is null', (tester) async {
      await _pump(
        tester,
        const AppRecoverableError(message: 'Read-only failure'),
      );

      expect(find.widgetWithText(ElevatedButton, 'Try again'), findsNothing);
    });

    testWidgets('exposes a semantics label for the error region', (
      tester,
    ) async {
      await _pump(tester, const AppRecoverableError(message: 'Boom'));

      expect(find.bySemanticsLabel('We hit a snag'), findsOneWidget);
    });
  });

  group('AppEmptyState', () {
    testWidgets('shows the message and no CTA by default', (tester) async {
      await _pump(tester, const AppEmptyState(message: 'Nothing here yet'));

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('renders a CTA when an action is provided', (tester) async {
      var tapped = 0;
      await _pump(
        tester,
        AppEmptyState(
          message: 'No expenses',
          actionLabel: 'Add expense',
          onAction: () => tapped++,
        ),
      );

      final cta = find.widgetWithText(ElevatedButton, 'Add expense');
      expect(cta, findsOneWidget);

      await tester.tap(cta);
      await tester.pump();
      expect(tapped, 1);
    });
  });
}
