import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/plans_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePurchaseCoordinator implements PurchaseCoordinator {
  _FakePurchaseCoordinator({this.packages = const []});

  final List<OfferingPackage> packages;
  int getPackagesCalls = 0;

  @override
  Future<void> configure({required String appUserId}) async {}

  @override
  Future<List<OfferingPackage>> getPackages() async {
    getPackagesCalls += 1;
    return packages;
  }

  @override
  Future<CustomerSubscriptionInfo> getCustomerInfo() async {
    return CustomerSubscriptionInfo.empty();
  }

  @override
  Future<PaywallPresentationResult> presentPaywallIfNeeded({
    String? offeringIdentifier,
  }) async {
    return PaywallPresentationResult.notSupported;
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

void main() {
  testWidgets('PlansScreen renders only live offer package cards', (
    tester,
  ) async {
    final coordinator = _FakePurchaseCoordinator(
      packages: const [
        OfferingPackage(
          id: 'annual',
          title: 'Buildozer Pro Annual',
          priceString: r'$95.99',
          periodLabel: 'year',
          productCode: 'annual',
          offeringId: 'default',
          packageType: 'annual',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [purchaseCoordinatorProvider.overrideWithValue(coordinator)],
        child: const MaterialApp(home: PlansScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Buildozer Pro Annual'), findsOneWidget);
    expect(find.text(r'$95.99 / year'), findsOneWidget);
    expect(find.text('Buildozer Pro Monthly'), findsNothing);
    expect(find.text(r'$9.99 / monthly'), findsNothing);
    expect(coordinator.getPackagesCalls, 1);
  });

  testWidgets('PlansScreen shows retryable unavailable state without prices', (
    tester,
  ) async {
    final coordinator = _FakePurchaseCoordinator();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [purchaseCoordinatorProvider.overrideWithValue(coordinator)],
        child: const MaterialApp(home: PlansScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Plans unavailable'), findsOneWidget);
    expect(
      find.text('Store offers are unavailable right now. Try again shortly.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets(
    'PlansScreen renders recommendation, comparison, and trial data',
    (tester) async {
      final coordinator = _FakePurchaseCoordinator(
        packages: const [
          OfferingPackage(
            id: 'monthly',
            title: 'Buildozer Pro Monthly',
            priceString: r'$12.99',
            periodLabel: 'month',
            productCode: 'monthly',
            offeringId: 'default',
            packageType: 'monthly',
            featureKeys: ['unlimited_projects'],
          ),
          OfferingPackage(
            id: 'annual',
            title: 'Buildozer Pro Annual',
            priceString: r'$95.99',
            periodLabel: 'year',
            productCode: 'annual',
            offeringId: 'default',
            packageType: 'annual',
            trialPeriodLabel: '7-day free trial',
            hasFreeTrial: true,
            isRecommended: true,
            featureKeys: ['unlimited_projects', 'priority_support'],
            savingsLabel: 'Save 20%',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            purchaseCoordinatorProvider.overrideWithValue(coordinator),
          ],
          child: const MaterialApp(home: PlansScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Save 20%'), findsOneWidget);
      expect(find.text('7-day free trial'), findsOneWidget);
      expect(find.text('Compare plans'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Unlimited projects'),
        250,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Unlimited projects'), findsWidgets);
      expect(find.text('Priority support'), findsOneWidget);
      expect(find.text('Included'), findsWidgets);
      expect(find.text('Not included'), findsOneWidget);
      expect(
        find.text(
          '7-day trial starts on first successful subscription purchase.',
        ),
        findsNothing,
      );
    },
  );
}
