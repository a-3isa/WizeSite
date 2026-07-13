import 'package:buildtrack_app/app/router.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  test('app router builds the review-pack route table', () {
    final auth = _MockFirebaseAuth();
    when(() => auth.authStateChanges()).thenAnswer((_) => const Stream.empty());
    when(() => auth.currentUser).thenReturn(_MockUser());
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        activeUserIdProvider.overrideWith((ref) => 'user_1'),
        activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);

    final routePaths = _routePaths(router.configuration.routes).toSet();
    expect(routePaths, contains(AppRoutes.initialWorkspaceSetup));
    expect(routePaths, contains(AppRoutes.workspaceSettings));
    expect(routePaths, contains(AppRoutes.entitySummary));
    expect(routePaths, contains(AppRoutes.syncStatus));
    expect(routePaths, contains(AppRoutes.paymentDetail));
    expect(routePaths, contains(AppRoutes.paymentEdit));
    expect(routePaths, contains(AppRoutes.workerAccounting));
    expect(routePaths, contains(AppRoutes.contractorsDirectory));
    expect(routePaths, contains(AppRoutes.equipmentDirectory));
    expect(routePaths, contains(AppRoutes.transportProvidersDirectory));
    expect(routePaths, contains(AppRoutes.login));
    expect(routePaths, contains(AppRoutes.signup));
    expect(routePaths, contains(AppRoutes.forgotPassword));
    expect(routePaths, isNot(contains('/add')));
    expect(routePaths, isNot(contains('/add-entry')));
  });

  test('resolveAppRedirect keeps authenticated workspace routes in app', () {
    expect(
      resolveAppRedirect(
        location: AppRoutes.paymentDetailPath(
          'payment_1',
          projectId: 'project_1',
        ),
        isSignedIn: true,
        hasWorkspace: true,
      ),
      isNull,
    );
    expect(
      resolveAppRedirect(
        location: AppRoutes.features,
        isSignedIn: true,
        hasWorkspace: true,
      ),
      AppRoutes.dashboard,
    );
  });

  test('resolveAppRedirect lets signed-out users reach the email auth screens', () {
    for (final route in [AppRoutes.signup, AppRoutes.forgotPassword]) {
      expect(
        resolveAppRedirect(
          location: route,
          isSignedIn: false,
          hasWorkspace: false,
        ),
        isNull,
        reason: '$route must stay reachable while signed out',
      );
    }
  });

  test('resolveAppRedirect holds an unverified user at the verify screen', () {
    // Any in-app destination bounces to verification...
    expect(
      resolveAppRedirect(
        location: AppRoutes.dashboard,
        isSignedIn: true,
        hasWorkspace: true,
        needsEmailVerification: true,
      ),
      AppRoutes.verifyEmail,
    );
    // ...and the verify screen itself stays reachable.
    expect(
      resolveAppRedirect(
        location: AppRoutes.verifyEmail,
        isSignedIn: true,
        hasWorkspace: false,
        needsEmailVerification: true,
      ),
      isNull,
    );
  });

  test('resolveAppRedirect releases a verified user from the verify screen', () {
    expect(
      resolveAppRedirect(
        location: AppRoutes.verifyEmail,
        isSignedIn: true,
        hasWorkspace: true,
        needsEmailVerification: false,
      ),
      AppRoutes.dashboard,
    );
  });

  test('resolveAppRedirect keeps signed-out users off the verify screen', () {
    expect(
      resolveAppRedirect(
        location: AppRoutes.verifyEmail,
        isSignedIn: false,
        hasWorkspace: false,
      ),
      AppRoutes.features,
    );
  });

  test('resolveAppRedirect pushes signed-in users off the email auth screens', () {
    for (final route in [AppRoutes.signup, AppRoutes.forgotPassword]) {
      expect(
        resolveAppRedirect(
          location: route,
          isSignedIn: true,
          hasWorkspace: true,
        ),
        AppRoutes.dashboard,
        reason: '$route must not be reachable once signed in',
      );
    }
  });

}

Iterable<String> _routePaths(List<RouteBase> routes) sync* {
  for (final route in routes) {
    if (route is GoRoute) {
      yield route.path;
      yield* _routePaths(route.routes);
    } else if (route is StatefulShellRoute) {
      for (final branch in route.branches) {
        yield* _routePaths(branch.routes);
      }
    }
  }
}
