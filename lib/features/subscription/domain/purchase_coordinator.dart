class OfferingPackage {
  const OfferingPackage({
    required this.id,
    required this.title,
    required this.priceString,
    required this.periodLabel,
    required this.productCode,
    required this.offeringId,
  });

  final String id;
  final String title;
  final String priceString;
  final String periodLabel;
  final String productCode;
  final String offeringId;
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
