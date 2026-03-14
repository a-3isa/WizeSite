import 'package:buildtrack_app/app/router.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signed-out user hitting protected route is redirected to features', () {
    final redirect = resolveAppRedirect(
      location: AppRoutes.dashboard,
      isSignedIn: false,
      hasWorkspace: false,
    );

    expect(redirect, AppRoutes.features);
  });

  test('signed-in user hitting auth route is redirected to root', () {
    final redirect = resolveAppRedirect(
      location: AppRoutes.login,
      isSignedIn: true,
      hasWorkspace: false,
    );

    expect(redirect, AppRoutes.root);
  });

  test('signed-in user with workspace is redirected away from onboarding', () {
    final redirect = resolveAppRedirect(
      location: AppRoutes.onboarding,
      isSignedIn: true,
      hasWorkspace: true,
    );

    expect(redirect, AppRoutes.dashboard);
  });
}
