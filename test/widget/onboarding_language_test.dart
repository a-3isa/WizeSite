import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'onboarding starts with language chooser and applies locale selection',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          localeControllerProvider.overrideWith(
            (ref) => LocaleController(deviceLocale: const Locale('en')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
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
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Choose your language'), findsOneWidget);
      expect(container.read(localeControllerProvider).languageCode, 'en');

      await tester.tap(find.text('Arabic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(container.read(localeControllerProvider).languageCode, 'ar');
      expect(find.text('تابع المشاريع'), findsOneWidget);
    },
  );
}
