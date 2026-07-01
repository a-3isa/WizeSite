import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfferingPackage metadata', () {
    test(
      'defaults keep backward compatibility (no trial, not recommended)',
      () {
        const package = OfferingPackage(
          id: 'pro_monthly',
          title: 'Pro Monthly',
          priceString: r'$9.99',
          periodLabel: 'month',
          productCode: 'pro_monthly',
          offeringId: 'default',
        );

        expect(package.packageType, isNull);
        expect(package.trialPeriodLabel, isNull);
        expect(package.hasFreeTrial, isFalse);
        expect(package.isRecommended, isFalse);
        expect(package.featureKeys, isEmpty);
        expect(package.savingsLabel, isNull);
      },
    );

    test(
      'carries trial, recommendation, and feature metadata when provided',
      () {
        const package = OfferingPackage(
          id: 'pro_annual',
          title: 'Pro Annual',
          priceString: r'$95.99',
          periodLabel: 'year',
          productCode: 'pro_annual',
          offeringId: 'default',
          packageType: 'annual',
          trialPeriodLabel: '7-day free trial',
          hasFreeTrial: true,
          isRecommended: true,
          featureKeys: ['unlimited_projects', 'priority_support'],
          savingsLabel: 'Save 20%',
        );

        expect(package.packageType, 'annual');
        expect(package.trialPeriodLabel, '7-day free trial');
        expect(package.hasFreeTrial, isTrue);
        expect(package.isRecommended, isTrue);
        expect(package.featureKeys, ['unlimited_projects', 'priority_support']);
        expect(package.savingsLabel, 'Save 20%');
      },
    );

    test('copyWith overrides only the provided fields', () {
      const base = OfferingPackage(
        id: 'pro_monthly',
        title: 'Pro Monthly',
        priceString: r'$9.99',
        periodLabel: 'month',
        productCode: 'pro_monthly',
        offeringId: 'default',
      );

      final recommended = base.copyWith(
        isRecommended: true,
        savingsLabel: 'Best value',
      );

      expect(recommended.isRecommended, isTrue);
      expect(recommended.savingsLabel, 'Best value');
      // Untouched fields are preserved.
      expect(recommended.id, 'pro_monthly');
      expect(recommended.priceString, r'$9.99');
      expect(recommended.hasFreeTrial, isFalse);
    });
  });
}
