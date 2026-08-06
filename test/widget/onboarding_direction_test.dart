import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        return MaterialApp(
          locale: ref.watch(localeControllerProvider),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen(),
        );
      },
    ),
  );
}

ProviderContainer _container(String lang) => ProviderContainer(
  overrides: [
    localeControllerProvider.overrideWith(
      (ref) => LocaleController(deviceLocale: Locale(lang)),
    ),
  ],
);

/// Centre-x of the wide (active) page indicator dot.
double _activeDotX(WidgetTester tester) {
  for (final e in find.byType(AnimatedContainer).evaluate()) {
    final f = find.byWidget(e.widget);
    if (tester.getSize(f).width > 20) return tester.getCenter(f).dx;
  }
  throw StateError('no active dot found');
}

void main() {
  group('onboarding paging direction', () {
    /// Advances one page and returns how far the active dot moved (+ = right).
    Future<double> indicatorDelta(WidgetTester tester, String lang) async {
      final container = _container(lang);
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();

      final next = lang == 'en' ? 'Next' : 'التالي';
      await tester.tap(find.text(next));
      await tester.pumpAndSettle();

      final before = _activeDotX(tester);
      await tester.tap(find.text(next));
      await tester.pumpAndSettle();
      return _activeDotX(tester) - before;
    }

    // Each locale runs in its own test: reusing one tester across locales keeps
    // the old _OnboardingScreenState (and its page index) alive.
    testWidgets('en advances the indicator to the right', (tester) async {
      expect(await indicatorDelta(tester, 'en'), 16.0);
    });

    testWidgets('ar advances the indicator the same way as en', (tester) async {
      expect(
        await indicatorDelta(tester, 'ar'),
        16.0,
        reason: 'ar indicator must advance in the same direction as en',
      );
    });

    testWidgets('indicator does not jump when locale switches to ar', (
      tester,
    ) async {
      final container = _container('en');
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Arabic'));
      await tester.pumpAndSettle();

      final before = _activeDotX(tester);

      // Tap "Next": this applies the ar locale AND animates to the next page.
      // Regression: the indicator row used to mirror instantly here, teleporting
      // the active dot across the row while the page was still animating.
      await tester.tap(find.text('Next'));
      var maxJump = 0.0;
      var previous = before;
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        final now = _activeDotX(tester);
        maxJump = maxJump > (now - previous).abs()
            ? maxJump
            : (now - previous).abs();
        previous = now;
      }
      await tester.pumpAndSettle();

      expect(
        maxJump,
        lessThan(20.0),
        reason: 'active dot must not teleport when the locale flips to ar',
      );
      // And it must still end up advancing to the right, like en.
      expect(_activeDotX(tester), greaterThan(before));
    });

    testWidgets('page content still renders right-to-left in ar', (
      tester,
    ) async {
      final container = _container('ar');
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.text('اختر لغتك'))),
        TextDirection.rtl,
      );
    });
  });
}
