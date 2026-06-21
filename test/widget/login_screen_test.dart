import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  Future<ProviderContainer> pumpLogin({
    required WidgetTester tester,
    required FirebaseAuth auth,
    required WorkspaceMutationService workspaceService,
    Future<bool> Function()? googleSupport,
    String? activeUserId,
    String? activeWorkspaceId,
  }) async {
    late ProviderContainer container;
    final router = GoRouter(
      initialLocation: AppRoutes.login,
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context, listen: false);
              return const LoginScreen();
            },
          ),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (context, state) =>
              const Text('Dashboard', textDirection: TextDirection.ltr),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          workspaceMutationServiceProvider.overrideWithValue(workspaceService),
          googleSignInSupportedProvider.overrideWith(
            (ref) => googleSupport?.call() ?? Future.value(false),
          ),
          activeUserIdProvider.overrideWith((ref) => activeUserId),
          activeWorkspaceIdProvider.overrideWith((ref) => activeWorkspaceId),
        ],
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
    return container;
  }

  void stubSuccessfulAuth({
    required _MockFirebaseAuth auth,
    required _MockUserCredential credential,
    required _MockUser user,
  }) {
    when(
      () => auth.signInWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => credential);
    when(() => credential.user).thenReturn(user);
    when(() => user.uid).thenReturn('user_1');
    when(() => auth.signOut()).thenAnswer((_) async {});
  }

  Future<void> submitLogin(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'USER@X.COM',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'LoginScreen uses local branding assets and keeps Google slot stable',
    (tester) async {
      final auth = _MockFirebaseAuth();
      final workspaceService = _MockWorkspaceMutationService();

      await pumpLogin(
        tester: tester,
        auth: auth,
        workspaceService: workspaceService,
        googleSupport: () async => true,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_app_icon')), findsOneWidget);
      expect(
        find.image(const AssetImage('assets/branding/app_icon.png')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('google_sign_in_slot')), findsOneWidget);
      expect(
        find.image(const AssetImage('assets/branding/google_g.png')),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNWidgets(2));
    },
  );

  testWidgets('LoginScreen preserves Google slot when support check fails', (
    tester,
  ) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();

    await pumpLogin(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
      googleSupport: () async => throw Exception('platform check failed'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('google_sign_in_slot')), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets(
    'LoginScreen validates fields inline and reveals password on request',
    (tester) async {
      final auth = _MockFirebaseAuth();
      final workspaceService = _MockWorkspaceMutationService();

      await pumpLogin(
        tester: tester,
        auth: auth,
        workspaceService: workspaceService,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);

      final passwordField = find.widgetWithText(TextField, 'Password');
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

      await tester.tap(find.byKey(const Key('password_visibility_toggle')));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
    },
  );

  testWidgets('LoginScreen routes restored sessions away from login', (
    tester,
  ) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();

    await pumpLogin(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
      activeUserId: 'user_1',
      activeWorkspaceId: 'workspace_1',
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets(
    'LoginScreen signs out when workspace bootstrap fails after auth success',
    (tester) async {
      final auth = _MockFirebaseAuth();
      final credential = _MockUserCredential();
      final user = _MockUser();
      final workspaceService = _MockWorkspaceMutationService();

      stubSuccessfulAuth(auth: auth, credential: credential, user: user);
      when(() => workspaceService.ensureUserWorkspaceBootstrap()).thenThrow(
        const CallableClientException('Failed to set up your workspace.'),
      );

      final container = await pumpLogin(
        tester: tester,
        auth: auth,
        workspaceService: workspaceService,
      );

      await submitLogin(tester);

      verify(() => auth.signOut()).called(1);
      expect(container.read(activeUserIdProvider), isNull);
      expect(container.read(activeWorkspaceIdProvider), isNull);
      expect(
        find.text(
          'Sign-in failed. Please check your email and password and try again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'LoginScreen rejects empty workspace bootstrap result after auth success',
    (tester) async {
      final auth = _MockFirebaseAuth();
      final credential = _MockUserCredential();
      final user = _MockUser();
      final workspaceService = _MockWorkspaceMutationService();

      stubSuccessfulAuth(auth: auth, credential: credential, user: user);
      when(
        () => workspaceService.ensureUserWorkspaceBootstrap(),
      ).thenAnswer((_) async => '   ');

      final container = await pumpLogin(
        tester: tester,
        auth: auth,
        workspaceService: workspaceService,
      );

      await submitLogin(tester);

      verify(() => auth.signOut()).called(1);
      expect(container.read(activeUserIdProvider), isNull);
      expect(container.read(activeWorkspaceIdProvider), isNull);
      expect(
        find.text(
          'Sign-in failed. Please check your email and password and try again.',
        ),
        findsOneWidget,
      );
    },
  );
}
