class OfferingPackage {
  const OfferingPackage({
    required this.id,
    required this.title,
    required this.priceString,
    required this.periodLabel,
    required this.productCode,
    required this.offeringId,
    this.packageType,
    this.trialPeriodLabel,
    this.hasFreeTrial = false,
    this.isRecommended = false,
    this.featureKeys = const [],
    this.savingsLabel,
  });

  final String id;
  final String title;
  final String priceString;
  final String periodLabel;
  final String productCode;
  final String offeringId;

  /// Store package type (e.g. `monthly`, `annual`). Null when unknown.
  final String? packageType;

  /// Localized/explicit trial label (e.g. `7-day free trial`). Null when the
  /// package has no introductory trial.
  final String? trialPeriodLabel;

  /// Whether the store reports an introductory free trial for this package.
  final bool hasFreeTrial;

  /// Recommendation input used to highlight a plan in the comparison UI.
  final bool isRecommended;

  /// Local feature-comparison content keys associated with this package.
  final List<String> featureKeys;

  /// Optional savings/value framing (e.g. `Save 20%`). Null when not applicable.
  final String? savingsLabel;

  OfferingPackage copyWith({
    String? id,
    String? title,
    String? priceString,
    String? periodLabel,
    String? productCode,
    String? offeringId,
    String? packageType,
    String? trialPeriodLabel,
    bool? hasFreeTrial,
    bool? isRecommended,
    List<String>? featureKeys,
    String? savingsLabel,
  }) {
    return OfferingPackage(
      id: id ?? this.id,
      title: title ?? this.title,
      priceString: priceString ?? this.priceString,
      periodLabel: periodLabel ?? this.periodLabel,
      productCode: productCode ?? this.productCode,
      offeringId: offeringId ?? this.offeringId,
      packageType: packageType ?? this.packageType,
      trialPeriodLabel: trialPeriodLabel ?? this.trialPeriodLabel,
      hasFreeTrial: hasFreeTrial ?? this.hasFreeTrial,
      isRecommended: isRecommended ?? this.isRecommended,
      featureKeys: featureKeys ?? this.featureKeys,
      savingsLabel: savingsLabel ?? this.savingsLabel,
    );
  }
}

class CustomerSubscriptionInfo {
  CustomerSubscriptionInfo({
    required this.appUserId,
    required this.hasProEntitlement,
    required this.isInTrial,
    required this.willRenew,
    required this.entitlementId,
    required this.productIdentifier,
    required this.requestDate,
    this.managementUrl,
    this.latestExpirationDate,
  });

  final String appUserId;
  final bool hasProEntitlement;
  final bool isInTrial;
  final bool willRenew;
  final String entitlementId;
  final String productIdentifier;
  final DateTime requestDate;
  final String? managementUrl;
  final DateTime? latestExpirationDate;

  factory CustomerSubscriptionInfo.empty() {
    return CustomerSubscriptionInfo(
      appUserId: '',
      hasProEntitlement: false,
      isInTrial: false,
      willRenew: false,
      entitlementId: '',
      productIdentifier: '',
      requestDate: DateTime.fromMillisecondsSinceEpoch(0),
      managementUrl: null,
      latestExpirationDate: null,
    );
  }
}

enum PaywallPresentationResult {
  purchased,
  restored,
  cancelled,
  notPresented,
  error,
  notSupported,
}

abstract interface class PurchaseCoordinator {
  Future<void> configure({required String appUserId});
  Future<List<OfferingPackage>> getPackages();
  Future<bool> purchase(String packageId);
  Future<bool> restore();
  Future<CustomerSubscriptionInfo> getCustomerInfo();
  Stream<CustomerSubscriptionInfo> watchCustomerInfo();
  Future<PaywallPresentationResult> presentPaywallIfNeeded({
    String? offeringIdentifier,
  });
  Future<void> presentCustomerCenter();
}
