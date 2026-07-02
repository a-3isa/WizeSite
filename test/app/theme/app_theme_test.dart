import 'package:buildtrack_app/app/theme/app_theme.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('light registers the light BuildTokens', (tester) async {
    late ThemeData captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(const Locale('en')),
        home: Builder(
          builder: (context) {
            captured = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(captured.brightness, Brightness.light);
    expect(captured.extension<BuildTokens>(), BuildTokens.light);
    expect(captured.scaffoldBackgroundColor, BuildTokens.light.bg);
  });

  testWidgets('dark registers the dark BuildTokens', (tester) async {
    late ThemeData captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(const Locale('en')),
        home: Builder(
          builder: (context) {
            captured = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(captured.brightness, Brightness.dark);
    expect(captured.extension<BuildTokens>(), BuildTokens.dark);
    expect(captured.scaffoldBackgroundColor, BuildTokens.dark.bg);
  });
}
