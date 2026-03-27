import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/subscription/domain/entitlement_guard_service.dart';
import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_repository.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_quota_repository.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/limit_reached_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeSubscriptionRepository implements SubscriptionRepository {
  @override
  Future<SubscriptionState> getSubscription(String workspaceId) async {
    return SubscriptionState.free();
  }

  @override
  Stream<SubscriptionState> watchSubscription(String workspaceId) {
    return Stream.value(SubscriptionState.free());
  }
}

class _FakeUsageQuotaRepository implements UsageQuotaRepository {
  @override
  Future<LimitCheckResult> checkLimit({
    required String workspaceId,
    required LimitType type,
    required int delta,
  }) async {
    return LimitCheckResult(
      allowed: false,
      limitType: type,
      current: 30,
      max: 30,
    );
  }

  @override
  Future<UsageSnapshot> getUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) async {
    return UsageSnapshot.empty(limits: limits);
  }

  @override
  Stream<UsageSnapshot> watchUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) {
    return Stream.value(UsageSnapshot.empty(limits: limits));
  }
}

class _FakeEntitlementGuard extends EntitlementGuardService {
  _FakeEntitlementGuard(this.result)
    : super(
        subscriptionRepository: _FakeSubscriptionRepository(),
        usageQuotaRepository: _FakeUsageQuotaRepository(),
      );

  final LimitCheckResult result;

  @override
  Future<LimitCheckResult> checkQuota({
    required String workspaceId,
    required LimitType type,
    int delta = 1,
  }) async {
    return result;
  }
}

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
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/subscription/limit',
        builder: (context, state) => LimitReachedScreen(
          limitType: state.uri.queryParameters['limit'] ?? 'generic',
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
      GoRoute(
        path: '/add-expense',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Add Expense Screen'))),
      ),
      GoRoute(
        path: '/add-payment',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Add Payment Screen'))),
      ),
      GoRoute(
        path: '/worker-entry/new',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Add Worker Entry Screen')),
        ),
      ),
      GoRoute(
        path: '/create-project',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Create Project Screen'))),
      ),
    ],
  );
}

Widget _testApp({
  required LimitCheckResult result,
  PaywallPresentationResult paywallResult =
      PaywallPresentationResult.notSupported,
}) {
  final usageSnapshot = UsageSnapshot(
    periodKey: '202603',
    activeProjects: result.limitType == LimitType.activeProjects
        ? result.current
        : 1,
    expensesCount: result.limitType == LimitType.expensesPerMonth
        ? result.current
        : 10,
    paymentsCount: result.limitType == LimitType.paymentsPerMonth
        ? result.current
        : 10,
    workerEntriesCount: result.limitType == LimitType.workerEntriesPerMonth
        ? result.current
        : 10,
    memberCount: result.limitType == LimitType.teamMembers ? result.current : 1,
    limits: PlanLimits.free(),
  );

  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_test'),
      currentSubscriptionStreamProvider.overrideWith(
        (ref) => Stream.value(
          SubscriptionState(
            tier: PlanTier.free,
            status: SubscriptionStatus.expired,
            store: 'none',
            isAutoRenewing: false,
            lastSyncedAt: DateTime.now(),
          ),
        ),
      ),
      currentUsageProvider.overrideWith(
        (ref) => Stream.value(usageSnapshot),
      ),
      dashboardSummaryProvider.overrideWith(
        (ref, workspaceId) => Stream.value({
          'totalProjects': 1,
          'activeProjects': 1,
          'totalExpenses': 1000,
          'totalIncome': 1200,
          'net': 200,
        }),
      ),
      entitlementGuardProvider.overrideWithValue(_FakeEntitlementGuard(result)),
      purchaseCoordinatorProvider.overrideWithValue(
        _FakePurchaseCoordinator(paywallResult),
      ),
    ],
    child: MaterialApp.router(routerConfig: _buildRouter()),
  );
}

void main() {
  testWidgets('navigates to paywall on cap hit', (tester) async {
    await tester.pumpWidget(
      _testApp(
        result: const LimitCheckResult(
          allowed: false,
          limitType: LimitType.expensesPerMonth,
          current: 30,
          max: 30,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final target = find.byKey(const Key('qa_add_expense'));
    await tester.scrollUntilVisible(target, 300, scrollable: scrollable);
    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(find.text('Upgrade Required'), findsOneWidget);
  });

  testWidgets('limit screen upgrade opens paywall success path', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        result: const LimitCheckResult(
          allowed: false,
          limitType: LimitType.expensesPerMonth,
          current: 30,
          max: 30,
        ),
        paywallResult: PaywallPresentationResult.purchased,
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final target = find.byKey(const Key('qa_add_expense'));
    await tester.scrollUntilVisible(target, 300, scrollable: scrollable);
    await tester.tap(target);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upgrade to Pro'));
    await tester.pumpAndSettle();

    expect(find.text('Subscription Success Screen'), findsOneWidget);
  });

  testWidgets('navigates to add expense when quota allows', (tester) async {
    await tester.pumpWidget(
      _testApp(
        result: const LimitCheckResult(
          allowed: true,
          limitType: LimitType.expensesPerMonth,
          current: 10,
          max: 30,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final target = find.byKey(const Key('qa_add_expense'));
    await tester.scrollUntilVisible(target, 300, scrollable: scrollable);
    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(find.text('Add Expense Screen'), findsOneWidget);
  });
}
