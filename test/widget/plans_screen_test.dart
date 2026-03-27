import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/plans_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePurchaseCoordinator implements PurchaseCoordinator {
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
  testWidgets('PlansScreen renders fallback package cards', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          purchaseCoordinatorProvider.overrideWithValue(
            _FakePurchaseCoordinator(),
          ),
        ],
        child: const MaterialApp(home: PlansScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Buildozer Pro Monthly'), findsOneWidget);
    expect(find.text('Buildozer Pro Yearly'), findsOneWidget);
    expect(find.text('Buildozer Pro Lifetime'), findsOneWidget);
    expect(
      find.text(
        '7-day trial starts on first successful subscription purchase.',
      ),
      findsOneWidget,
    );
  });
}
