import 'dart:async';

import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class RevenueCatPurchaseCoordinator implements PurchaseCoordinator {
  RevenueCatPurchaseCoordinator({
    String? apiKey,
    String? entitlementId,
    String? defaultOfferingId,
  }) : _apiKey =
           apiKey ??
           const String.fromEnvironment(
             'REVENUECAT_API_KEY',
             defaultValue: 'test_xrxXJcTowFByLKxcgDhWpeEmBir',
           ),
       _entitlementId =
           entitlementId ??
           const String.fromEnvironment(
             'REVENUECAT_ENTITLEMENT_ID',
             defaultValue: 'wizesite_pro',
           ),
       _defaultOfferingId = defaultOfferingId;

  final String _apiKey;
  final String _entitlementId;
  final String? _defaultOfferingId;

  bool _configured = false;
  bool _customerListenerAttached = false;
  String? _currentAppUserId;

  final Map<String, Package> _cache = <String, Package>{};
  final StreamController<CustomerSubscriptionInfo> _customerInfoController =
      StreamController<CustomerSubscriptionInfo>.broadcast();

  bool get _supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> configure({required String appUserId}) async {
    if (!_supportedPlatform) {
      return;
    }
    if (_apiKey.isEmpty) {
      throw StateError(
        'RevenueCat API key is missing. Pass REVENUECAT_API_KEY via --dart-define.',
      );
    }

    if (!_configured) {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      final configuration = PurchasesConfiguration(_apiKey)
        ..appUserID = appUserId;
      await Purchases.configure(configuration);
      _configured = true;
      _currentAppUserId = appUserId;
      _attachCustomerInfoListener();
    } else if (_currentAppUserId != appUserId) {
      await Purchases.logIn(appUserId);
      _currentAppUserId = appUserId;
    }

    await Purchases.setAttributes({
      'workspace_id': appUserId,
      'app_user_id': appUserId,
    });
    await _refreshCustomerInfo();
  }

  @override
  Future<List<OfferingPackage>> getPackages() async {
    if (!_configured || !_supportedPlatform) {
      return const [];
    }

    final offerings = await Purchases.syncAttributesAndOfferingsIfNeeded();
    final offering = _resolveOffering(offerings, null);
    if (offering == null) {
      return const [];
    }

    final ordered = _orderedPackages(offering.availablePackages);
    _cache
      ..clear()
      ..addEntries(ordered.map((pkg) => MapEntry(pkg.identifier, pkg)));

    return ordered
        .map(
          (pkg) => OfferingPackage(
            id: pkg.identifier,
            title: pkg.storeProduct.title,
            priceString: pkg.storeProduct.priceString,
            periodLabel: _periodLabel(pkg.packageType),
            productCode: _productCode(pkg.packageType),
            offeringId: pkg.presentedOfferingContext.offeringIdentifier,
          ),
        )
        .toList();
  }

  @override
  Future<bool> purchase(String packageId) async {
    if (!_configured || !_supportedPlatform) {
      return false;
    }
    final package = _cache[packageId];
    if (package == null) {
      return false;
    }

    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _emit(result.customerInfo);
      return _hasProEntitlement(result.customerInfo);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      throw StateError(
        'Purchase failed (${code.name}): ${e.message ?? 'Unknown RevenueCat error'}',
      );
    }
  }

  @override
  Future<bool> restore() async {
    if (!_configured || !_supportedPlatform) {
      return false;
    }
    try {
      final customerInfo = await Purchases.restorePurchases();
      _emit(customerInfo);
      return _hasProEntitlement(customerInfo);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      throw StateError(
        'Restore failed (${code.name}): ${e.message ?? 'Unknown RevenueCat error'}',
      );
    }
  }

  @override
  Future<CustomerSubscriptionInfo> getCustomerInfo() async {
    if (!_configured || !_supportedPlatform) {
      return CustomerSubscriptionInfo.empty();
    }
    final customerInfo = await Purchases.getCustomerInfo();
    final mapped = _mapCustomerInfo(customerInfo);
    _customerInfoController.add(mapped);
    return mapped;
  }

  @override
  Stream<CustomerSubscriptionInfo> watchCustomerInfo() async* {
    if (!_supportedPlatform) {
      yield CustomerSubscriptionInfo.empty();
      return;
    }
    if (_configured) {
      yield await getCustomerInfo();
    } else {
      yield CustomerSubscriptionInfo.empty();
    }
    yield* _customerInfoController.stream;
  }

  @override
  Future<PaywallPresentationResult> presentPaywallIfNeeded({
    String? offeringIdentifier,
  }) async {
    if (!_configured || !_supportedPlatform) {
      return PaywallPresentationResult.notSupported;
    }

    try {
      final offerings = await Purchases.syncAttributesAndOfferingsIfNeeded();
      final offering = _resolveOffering(offerings, offeringIdentifier);
      final result = await RevenueCatUI.presentPaywallIfNeeded(
        _entitlementId,
        offering: offering,
        displayCloseButton: true,
      );

      if (result == PaywallResult.purchased ||
          result == PaywallResult.restored) {
        await _refreshCustomerInfo();
      }

      return _mapPaywallResult(result);
    } on PlatformException {
      return PaywallPresentationResult.error;
    }
  }

  @override
  Future<void> presentCustomerCenter() async {
    if (!_configured || !_supportedPlatform) {
      return;
    }
    await RevenueCatUI.presentCustomerCenter(
      onRestoreCompleted: (customerInfo) => _emit(customerInfo),
    );
  }

  void _attachCustomerInfoListener() {
    if (_customerListenerAttached) {
      return;
    }
    Purchases.addCustomerInfoUpdateListener(_emit);
    _customerListenerAttached = true;
  }

  Future<void> _refreshCustomerInfo() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _emit(info);
    } on PlatformException {
      // Keep app flow resilient if storefront is unavailable temporarily.
    }
  }

  void _emit(CustomerInfo customerInfo) {
    _customerInfoController.add(_mapCustomerInfo(customerInfo));
  }

  CustomerSubscriptionInfo _mapCustomerInfo(CustomerInfo customerInfo) {
    final activeEntitlement = _resolveEntitlement(customerInfo);
    return CustomerSubscriptionInfo(
      appUserId: customerInfo.originalAppUserId,
      hasProEntitlement: activeEntitlement?.isActive ?? false,
      isInTrial: activeEntitlement?.periodType == PeriodType.trial,
      willRenew: activeEntitlement?.willRenew ?? false,
      entitlementId: activeEntitlement?.identifier ?? _entitlementId,
      productIdentifier: activeEntitlement?.productIdentifier ?? '',
      requestDate:
          DateTime.tryParse(customerInfo.requestDate) ?? DateTime.now(),
      managementUrl: customerInfo.managementURL,
      latestExpirationDate: customerInfo.latestExpirationDate == null
          ? null
          : DateTime.tryParse(customerInfo.latestExpirationDate!),
    );
  }

  EntitlementInfo? _resolveEntitlement(CustomerInfo info) {
    final active = info.entitlements.active;
    if (active.containsKey(_entitlementId)) {
      return active[_entitlementId];
    }

    final normalizedTarget = _normalize(_entitlementId);
    for (final entry in active.entries) {
      final normalizedKey = _normalize(entry.key);
      if (normalizedKey == normalizedTarget ||
          normalizedKey == 'wizesitepro' ||
          normalizedKey.contains('pro')) {
        return entry.value;
      }
    }
    return null;
  }

  bool _hasProEntitlement(CustomerInfo customerInfo) {
    return _resolveEntitlement(customerInfo) != null;
  }

  Offering? _resolveOffering(Offerings offerings, String? offeringIdentifier) {
    final desired = offeringIdentifier ?? _defaultOfferingId;
    if (desired != null && desired.isNotEmpty) {
      final match = offerings.getOffering(desired);
      if (match != null) {
        return match;
      }
    }
    return offerings.current;
  }

  List<Package> _orderedPackages(List<Package> packages) {
    final sorted = List<Package>.from(packages);
    sorted.sort(
      (a, b) => _packageRank(a.packageType) - _packageRank(b.packageType),
    );
    return sorted;
  }

  int _packageRank(PackageType type) {
    switch (type) {
      case PackageType.monthly:
        return 0;
      case PackageType.annual:
        return 1;
      case PackageType.lifetime:
        return 2;
      default:
        return 3;
    }
  }

  String _periodLabel(PackageType type) {
    switch (type) {
      case PackageType.monthly:
        return 'monthly';
      case PackageType.annual:
        return 'yearly';
      case PackageType.lifetime:
        return 'lifetime';
      case PackageType.weekly:
        return 'weekly';
      case PackageType.sixMonth:
        return '6 months';
      case PackageType.threeMonth:
        return '3 months';
      case PackageType.twoMonth:
        return '2 months';
      default:
        return 'custom';
    }
  }

  String _productCode(PackageType type) {
    switch (type) {
      case PackageType.monthly:
        return 'monthly';
      case PackageType.annual:
        return 'yearly';
      case PackageType.lifetime:
        return 'lifetime';
      default:
        return 'custom';
    }
  }

  PaywallPresentationResult _mapPaywallResult(PaywallResult result) {
    switch (result) {
      case PaywallResult.purchased:
        return PaywallPresentationResult.purchased;
      case PaywallResult.restored:
        return PaywallPresentationResult.restored;
      case PaywallResult.cancelled:
        return PaywallPresentationResult.cancelled;
      case PaywallResult.notPresented:
        return PaywallPresentationResult.notPresented;
      case PaywallResult.error:
        return PaywallPresentationResult.error;
    }
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
