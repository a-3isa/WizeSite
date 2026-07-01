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

  testWidgets('LoginScreen is Google-only and keeps the Google slot stable', (
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
    expect(find.widgetWithText(TextField, 'Email'), findsNothing);
    expect(find.widgetWithText(TextField, 'Password'), findsNothing);
    expect(find.text('Forgot Password'), findsNothing);
    expect(find.text("Don't have an account?"), findsNothing);
    expect(find.text('Sign Up'), findsNothing);
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
