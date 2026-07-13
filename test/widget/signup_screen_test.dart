import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/signup_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

void main() {
  Future<void> pumpSignUp({
    required WidgetTester tester,
    required FirebaseAuth auth,
    required WorkspaceMutationService workspaceService,
  }) async {
    final router = GoRouter(
      initialLocation: AppRoutes.signup,
      routes: [
        GoRoute(
          path: AppRoutes.signup,
          builder: (context, state) => const SignUpScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) =>
              const Text('Login', textDirection: TextDirection.ltr),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (context, state) =>
              const Text('Dashboard', textDirection: TextDirection.ltr),
        ),
        GoRoute(
          path: AppRoutes.initialWorkspaceSetup,
          builder: (context, state) =>
              const Text('Workspace Setup', textDirection: TextDirection.ltr),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          workspaceMutationServiceProvider.overrideWithValue(workspaceService),
          activeUserIdProvider.overrideWith((ref) => null),
          activeWorkspaceIdProvider.overrideWith((ref) => null),
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
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(
    WidgetTester tester, {
    String name = 'Sam Builder',
    String email = 'sam@example.com',
    String password = 'password123',
    String? confirm,
  }) async {
    await tester.enterText(find.byKey(const Key('qa_signup_name')), name);
    await tester.enterText(find.byKey(const Key('qa_signup_email')), email);
    await tester.enterText(
      find.byKey(const Key('qa_signup_password')),
      password,
    );
    await tester.enterText(
      find.byKey(const Key('qa_signup_confirm')),
      confirm ?? password,
    );
  }

  testWidgets('rejects a short password before calling Firebase', (
    tester,
  ) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();

    await pumpSignUp(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
    );
    await fillForm(tester, password: 'short');
    await tester.tap(find.byKey(const Key('qa_signup_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa_auth_error')), findsOneWidget);
    verifyNever(
      () => auth.createUserWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    );
  });

  testWidgets('rejects mismatched passwords before calling Firebase', (
    tester,
  ) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();

    await pumpSignUp(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
    );
    await fillForm(tester, password: 'password123', confirm: 'password124');
    await tester.tap(find.byKey(const Key('qa_signup_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    verifyNever(
      () => auth.createUserWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    );
  });

  testWidgets('rejects an empty name before calling Firebase', (tester) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();

    await pumpSignUp(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
    );
    await fillForm(tester, name: '  ');
    await tester.tap(find.byKey(const Key('qa_signup_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Enter your name.'), findsOneWidget);
    verifyNever(
      () => auth.createUserWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    );
  });

  testWidgets('surfaces an email-already-in-use failure', (tester) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();

    when(
      () => auth.createUserWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
    when(() => auth.signOut()).thenAnswer((_) async {});

    await pumpSignUp(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
    );
    await fillForm(tester);
    await tester.tap(find.byKey(const Key('qa_signup_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa_auth_error')), findsOneWidget);
    expect(find.byType(SignUpScreen), findsOneWidget);
  });

  testWidgets('creates the account, sets the display name, and bootstraps', (
    tester,
  ) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();
    final credential = _MockUserCredential();
    final user = _MockUser();

    when(() => user.uid).thenReturn('user_1');
    when(() => user.updateDisplayName(any())).thenAnswer((_) async {});
    when(() => user.reload()).thenAnswer((_) async {});
    when(() => credential.user).thenReturn(user);
    when(
      () => auth.createUserWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => credential);
    when(() => workspaceService.ensureUserWorkspaceBootstrap()).thenAnswer(
      (_) async => const WorkspaceBootstrapResult(
        workspaceId: 'workspace_1',
        created: true,
        setupCompleted: false,
      ),
    );

    await pumpSignUp(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
    );
    await fillForm(tester);
    await tester.tap(find.byKey(const Key('qa_signup_submit')));
    await tester.pumpAndSettle();

    verify(() => user.updateDisplayName('Sam Builder')).called(1);
    verify(() => workspaceService.ensureUserWorkspaceBootstrap()).called(1);
    // A brand-new workspace has not completed setup, so route there, not home.
    expect(find.text('Workspace Setup'), findsOneWidget);
  });
}
