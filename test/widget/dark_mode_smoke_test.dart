import 'package:buildtrack_app/app/theme/app_theme.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards that the dark theme is wired end-to-end: a widget reading
/// `context.tokens` resolves the dark palette when the app runs in dark mode.
void main() {
  testWidgets('dark theme resolves dark tokens through context', (
    tester,
  ) async {
    late BuildTokens resolved;
    late Color scaffoldBg;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(const Locale('en')),
        darkTheme: AppTheme.dark(const Locale('en')),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            resolved = context.tokens;
            scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    expect(resolved, BuildTokens.dark);
    expect(scaffoldBg, BuildTokens.dark.bg);
    expect(resolved.text, BuildTokens.dark.text);
  });

  testWidgets('light theme resolves light tokens through context', (
    tester,
  ) async {
    late BuildTokens resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(const Locale('en')),
        darkTheme: AppTheme.dark(const Locale('en')),
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (context) {
            resolved = context.tokens;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    expect(resolved, BuildTokens.light);
  });
}
