import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/verify_email_screen.dart';
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

class _MockUser extends Mock implements User {}

void main() {
  late _MockFirebaseAuth auth;
  late _MockWorkspaceMutationService workspaceService;
  late _MockUser user;

  setUp(() {
    auth = _MockFirebaseAuth();
    workspaceService = _MockWorkspaceMutationService();
    user = _MockUser();

    when(() => user.uid).thenReturn('user_1');
    when(() => user.email).thenReturn('sam@example.com');
    when(() => user.emailVerified).thenReturn(false);
    when(() => user.sendEmailVerification()).thenAnswer((_) async {});
    when(() => user.reload()).thenAnswer((_) async {});
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  Future<void> pumpVerify(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.verifyEmail,
      routes: [
        GoRoute(
          path: AppRoutes.verifyEmail,
          builder: (context, state) => const VerifyEmailScreen(),
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

  testWidgets('sends a verification email on arrival and starts the cooldown', (
    tester,
  ) async {
    await pumpVerify(tester);

    verify(() => user.sendEmailVerification()).called(1);
    expect(find.byKey(const Key('qa_auth_info')), findsOneWidget);
    // Resend is disabled while the cooldown runs.
    final resend = tester.widget<Widget>(find.byKey(const Key('qa_verify_resend')));
    expect(resend, isNotNull);
    expect(find.textContaining('Resend in'), findsOneWidget);
  });

  testWidgets('reports when the address is still unverified', (tester) async {
    await pumpVerify(tester);

    // Still unverified after reload.
    await tester.tap(find.byKey(const Key('qa_verify_continue')));
    await tester.pumpAndSettle();

    verify(() => user.reload()).called(1);
    expect(find.byKey(const Key('qa_auth_error')), findsOneWidget);
    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    // Crucially: no workspace was created for an unverified user.
    verifyNever(() => workspaceService.ensureUserWorkspaceBootstrap());
  });

  testWidgets('bootstraps the workspace only once verification passes', (
    tester,
  ) async {
    await pumpVerify(tester);

    final verifiedUser = _MockUser();
    when(() => verifiedUser.uid).thenReturn('user_1');
    when(() => verifiedUser.email).thenReturn('sam@example.com');
    when(() => verifiedUser.emailVerified).thenReturn(true);
    when(() => verifiedUser.reload()).thenAnswer((_) async {});
    when(() => workspaceService.ensureUserWorkspaceBootstrap()).thenAnswer(
      (_) async => const WorkspaceBootstrapResult(
        workspaceId: 'workspace_1',
        created: true,
        setupCompleted: false,
      ),
    );

    // The reload flips Firebase over to a verified user.
    when(() => auth.currentUser).thenReturn(verifiedUser);

    await tester.tap(find.byKey(const Key('qa_verify_continue')));
    await tester.pumpAndSettle();

    verify(() => workspaceService.ensureUserWorkspaceBootstrap()).called(1);
    expect(find.text('Workspace Setup'), findsOneWidget);
  });

  testWidgets('signing out returns to login', (tester) async {
    await pumpVerify(tester);

    await tester.tap(find.byKey(const Key('qa_verify_signout')));
    await tester.pumpAndSettle();

    verify(() => auth.signOut()).called(1);
    expect(find.text('Login'), findsOneWidget);
  });
}
