import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

void main() {
  Future<void> pumpForgot({
    required WidgetTester tester,
    required FirebaseAuth auth,
  }) async {
    final router = GoRouter(
      initialLocation: AppRoutes.forgotPassword,
      routes: [
        GoRoute(
          path: AppRoutes.forgotPassword,
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) =>
              const Text('Login', textDirection: TextDirection.ltr),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [firebaseAuthProvider.overrideWithValue(auth)],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('rejects a malformed email before calling Firebase', (
    tester,
  ) async {
    final auth = _MockFirebaseAuth();

    await pumpForgot(tester: tester, auth: auth);
    await tester.enterText(find.byKey(const Key('qa_forgot_email')), 'nope');
    await tester.tap(find.byKey(const Key('qa_forgot_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa_auth_error')), findsOneWidget);
    verifyNever(() => auth.sendPasswordResetEmail(email: any(named: 'email')));
  });

  testWidgets('confirms when the reset link is sent', (tester) async {
    final auth = _MockFirebaseAuth();
    when(
      () => auth.sendPasswordResetEmail(email: any(named: 'email')),
    ).thenAnswer((_) async {});

    await pumpForgot(tester: tester, auth: auth);
    await tester.enterText(
      find.byKey(const Key('qa_forgot_email')),
      'sam@example.com',
    );
    await tester.tap(find.byKey(const Key('qa_forgot_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa_auth_info')), findsOneWidget);
    expect(find.text('Reset link sent to your email.'), findsOneWidget);
    verify(
      () => auth.sendPasswordResetEmail(email: 'sam@example.com'),
    ).called(1);
  });

  testWidgets('does not reveal that an email is unregistered', (tester) async {
    final auth = _MockFirebaseAuth();
    when(
      () => auth.sendPasswordResetEmail(email: any(named: 'email')),
    ).thenThrow(FirebaseAuthException(code: 'user-not-found'));

    await pumpForgot(tester: tester, auth: auth);
    await tester.enterText(
      find.byKey(const Key('qa_forgot_email')),
      'ghost@example.com',
    );
    await tester.tap(find.byKey(const Key('qa_forgot_submit')));
    await tester.pumpAndSettle();

    // Identical to the success case: no account enumeration.
    expect(find.byKey(const Key('qa_auth_info')), findsOneWidget);
    expect(find.text('Reset link sent to your email.'), findsOneWidget);
    expect(find.byKey(const Key('qa_auth_error')), findsNothing);
  });

  testWidgets('surfaces a genuine failure', (tester) async {
    final auth = _MockFirebaseAuth();
    when(
      () => auth.sendPasswordResetEmail(email: any(named: 'email')),
    ).thenThrow(FirebaseAuthException(code: 'network-request-failed'));

    await pumpForgot(tester: tester, auth: auth);
    await tester.enterText(
      find.byKey(const Key('qa_forgot_email')),
      'sam@example.com',
    );
    await tester.tap(find.byKey(const Key('qa_forgot_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa_auth_error')), findsOneWidget);
    expect(find.byKey(const Key('qa_auth_info')), findsNothing);
  });
}
