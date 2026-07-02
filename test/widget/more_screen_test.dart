import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/app_theme.dart';
import 'package:buildtrack_app/core/providers/theme_provider.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/more_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dark-mode toggle drives the ThemeController', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(const Locale('en')),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MoreScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(themeControllerProvider), ThemeMode.system);
    await tester.tap(find.byKey(const Key('qa_more_dark_toggle')));
    await tester.pumpAndSettle();
    expect(container.read(themeControllerProvider), ThemeMode.dark);
  });
}
