import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
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

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

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

  testWidgets('LoginScreen offers both email and Google sign-in', (
    tester,
  ) async {
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
    expect(find.byKey(const Key('google_sign_in_slot')), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/branding/google_g.png')),
      findsOneWidget,
    );

    // Email/password path.
    expect(find.byKey(const Key('qa_login_email')), findsOneWidget);
    expect(find.byKey(const Key('qa_login_password')), findsOneWidget);
    expect(find.byKey(const Key('qa_login_submit')), findsOneWidget);
    expect(find.byKey(const Key('qa_login_forgot')), findsOneWidget);
    expect(find.byKey(const Key('qa_login_to_signup')), findsOneWidget);
  });

  testWidgets('LoginScreen rejects an empty email/password submit', (
    tester,
  ) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();

    await pumpLogin(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('qa_login_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa_auth_error')), findsOneWidget);
    expect(find.text('Please enter your email and password.'), findsOneWidget);
    // Never reached Firebase.
    verifyNever(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ));
  });

  testWidgets('LoginScreen rejects a malformed email before calling Firebase', (
    tester,
  ) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();

    await pumpLogin(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('qa_login_email')), 'not-email');
    await tester.enterText(
      find.byKey(const Key('qa_login_password')),
      'password123',
    );
    await tester.tap(find.byKey(const Key('qa_login_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa_auth_error')), findsOneWidget);
    verifyNever(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ));
  });

  testWidgets('LoginScreen surfaces a wrong-password failure', (tester) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();

    when(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(FirebaseAuthException(code: 'wrong-password'));
    when(() => auth.signOut()).thenAnswer((_) async {});

    await pumpLogin(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('qa_login_email')),
      'sam@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('qa_login_password')),
      'wrongpass1',
    );
    await tester.tap(find.byKey(const Key('qa_login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

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

  testWidgets('LoginScreen signs in with email and lands on the dashboard', (
    tester,
  ) async {
    final auth = _MockFirebaseAuth();
    final workspaceService = _MockWorkspaceMutationService();
    final credential = _MockUserCredential();
    final user = _MockUser();

    when(() => user.uid).thenReturn('user_1');
    when(() => credential.user).thenReturn(user);
    when(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => credential);
    when(() => workspaceService.ensureUserWorkspaceBootstrap()).thenAnswer(
      (_) async => const WorkspaceBootstrapResult(
        workspaceId: 'workspace_1',
        created: false,
        setupCompleted: true,
      ),
    );

    await pumpLogin(
      tester: tester,
      auth: auth,
      workspaceService: workspaceService,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('qa_login_email')),
      'sam@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('qa_login_password')),
      'password123',
    );
    await tester.tap(find.byKey(const Key('qa_login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    verify(() => workspaceService.ensureUserWorkspaceBootstrap()).called(1);
  });

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
}
