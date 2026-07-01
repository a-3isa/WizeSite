import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/limit_reached_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakePurchaseCoordinator implements PurchaseCoordinator {
  _FakePurchaseCoordinator(this._paywallResult);

  final PaywallPresentationResult _paywallResult;

  @override
  Future<void> configure({required String appUserId}) async {}

  @override
  Future<List<OfferingPackage>> getPackages() async => const [];

  @override
  Future<CustomerSubscriptionInfo> getCustomerInfo() async {
    return CustomerSubscriptionInfo.empty();
  }

  @override
  Future<PaywallPresentationResult> presentPaywallIfNeeded({
    String? offeringIdentifier,
  }) async {
    return _paywallResult;
  }

  @override
  Future<bool> purchase(String packageId) async => false;

  @override
  Future<void> presentCustomerCenter() async {}

  @override
  Future<bool> restore() async => false;

  @override
  Stream<CustomerSubscriptionInfo> watchCustomerInfo() {
    return const Stream<CustomerSubscriptionInfo>.empty();
  }
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Dashboard Screen'))),
      ),
      GoRoute(
        path: '/subscription/limit',
        builder: (context, state) => LimitReachedScreen(
          limitType: state.uri.queryParameters['limit'] ?? 'generic',
          current: int.tryParse(state.uri.queryParameters['current'] ?? ''),
          max: int.tryParse(state.uri.queryParameters['max'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/subscription/plans',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Plans Screen'))),
      ),
      GoRoute(
        path: '/subscription/success',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Subscription Success Screen')),
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('limit screen upgrade opens paywall success path directly', (
    tester,
  ) async {
    final router = _buildRouter();
    router.go('/subscription/limit?limit=expensesPerMonth');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_test'),
          purchaseCoordinatorProvider.overrideWithValue(
            _FakePurchaseCoordinator(PaywallPresentationResult.purchased),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upgrade to Pro'));
    await tester.pumpAndSettle();

    expect(find.text('Subscription Success Screen'), findsOneWidget);
  });

  testWidgets('limit screen explains blocked quota and opens plans directly', (
    tester,
  ) async {
    final router = _buildRouter();
    router.go('/subscription/limit?limit=expensesPerMonth&current=30&max=30');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_test'),
          purchaseCoordinatorProvider.overrideWithValue(
            _FakePurchaseCoordinator(PaywallPresentationResult.notSupported),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Monthly Expense Limit Reached'), findsOneWidget);
    expect(
      find.text(
        'You have used 30 of 30 monthly expense entries on the Free plan. Upgrade to Pro to keep adding expenses.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Upgrade to Pro'));
    await tester.pumpAndSettle();

    expect(find.text('Plans Screen'), findsOneWidget);
  });
}
