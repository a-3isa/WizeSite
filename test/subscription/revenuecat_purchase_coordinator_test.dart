import 'package:buildtrack_app/features/subscription/data/revenuecat_purchase_coordinator.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Package package({
    required String id,
    required PackageType type,
    required String title,
    required String priceString,
    IntroductoryPrice? introPrice,
  }) {
    return Package(
      id,
      type,
      StoreProduct(
        '$id.product',
        '$title description',
        title,
        95.99,
        priceString,
        'USD',
        introductoryPrice: introPrice,
      ),
      const PresentedOfferingContext('default', null, null),
    );
  }

  test('maps nullable package metadata without fabricating trial copy', () {
    final mapped = mapRevenueCatPackagesForTesting([
      package(
        id: 'monthly',
        type: PackageType.monthly,
        title: 'Buildozer Pro Monthly',
        priceString: r'$12.99',
      ),
    ]);

    expect(mapped, hasLength(1));
    expect(mapped.single.id, 'monthly');
    expect(mapped.single.priceString, r'$12.99');
    expect(mapped.single.packageType, 'monthly');
    expect(mapped.single.trialPeriodLabel, isNull);
    expect(mapped.single.hasFreeTrial, isFalse);
    expect(mapped.single.isRecommended, isFalse);
    expect(mapped.single.featureKeys, contains('unlimited_projects'));
  });

  test('maps free trial metadata and recommends the annual package', () {
    final mapped = mapRevenueCatPackagesForTesting([
      package(
        id: 'monthly',
        type: PackageType.monthly,
        title: 'Buildozer Pro Monthly',
        priceString: r'$12.99',
      ),
      package(
        id: 'annual',
        type: PackageType.annual,
        title: 'Buildozer Pro Annual',
        priceString: r'$95.99',
        introPrice: const IntroductoryPrice(
          0,
          r'$0.00',
          'P7D',
          1,
          PeriodUnit.day,
          7,
        ),
      ),
    ]);

    final annual = mapped.singleWhere((item) => item.id == 'annual');
    expect(annual.packageType, 'annual');
    expect(annual.hasFreeTrial, isTrue);
    expect(annual.trialPeriodLabel, '7-day free trial');
    expect(annual.isRecommended, isTrue);
    expect(annual.savingsLabel, isNotNull);
    expect(annual.featureKeys, contains('priority_support'));
  });

  test('empty RevenueCat package lists stay empty', () {
    expect(mapRevenueCatPackagesForTesting(const []), isEmpty);
  });
}
