import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

class ManageSubscriptionScreen extends ConsumerStatefulWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  ConsumerState<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState
    extends ConsumerState<ManageSubscriptionScreen> {
  bool _restoring = false;
  bool _openingCustomerCenter = false;
  String? _message;

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _restoring = true;
      _message = null;
    });
    final ok = await ref.read(purchaseCoordinatorProvider).restore();
    setState(() {
      _restoring = false;
      _message = ok
          ? l10n.t('purchasesRestoredSuccessfully')
          : l10n.t('noActivePurchasesFound');
    });
  }

  Future<void> _openCustomerCenter() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _openingCustomerCenter = true;
      _message = null;
    });
    try {
      await ref.read(purchaseCoordinatorProvider).presentCustomerCenter();
      if (mounted) {
        setState(() => _message = l10n.t('customerCenterClosed'));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = l10n.t(
            'customerCenterFailed',
            params: {'error': '$e'},
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _openingCustomerCenter = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.watch(revenueCatBootstrapProvider);
    final subAsync = ref.watch(currentSubscriptionStreamProvider);
    final customerInfoAsync = ref.watch(revenueCatCustomerInfoProvider);

    return AppBackScope(
      fallbackRoute: AppRoutes.settings,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('manageSubscription'),
          fallbackRoute: AppRoutes.settings,
        ),
        body: subAsync.whenStale(
          data: (sub) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  title: Text(
                    sub.tier == PlanTier.pro
                        ? l10n.t('tierPro')
                        : l10n.t('tierFree'),
                  ),
                  subtitle: Text(
                    '${l10n.t('status')}: ${l10n.subscriptionStatusLabel(sub.status.name)}',
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text(l10n.t('trialEndsAt')),
                  subtitle: Text(sub.trialEndsAt?.toIso8601String() ?? '-'),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text(l10n.t('currentPeriodEndsAt')),
                  subtitle: Text(sub.periodEndsAt?.toIso8601String() ?? '-'),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text(l10n.t('store')),
                  subtitle: Text(sub.store),
                ),
              ),
              customerInfoAsync.whenStale(
                data: (info) => Column(
                  children: [
                    Card(
                      child: ListTile(
                        title: Text(l10n.t('revenueCatAppUserId')),
                        subtitle: Text(
                          info.appUserId.isEmpty ? '-' : info.appUserId,
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        title: Text(l10n.t('wizeSiteProEntitlement')),
                        subtitle: Text(
                          info.hasProEntitlement
                              ? l10n.t('entitlementActive')
                              : l10n.t('entitlementInactive'),
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        title: Text(l10n.t('currentProduct')),
                        subtitle: Text(
                          info.productIdentifier.isEmpty
                              ? '-'
                              : info.productIdentifier,
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        title: Text(l10n.t('entitlementExpiration')),
                        subtitle: Text(
                          info.latestExpirationDate?.toIso8601String() ?? '-',
                        ),
                      ),
                    ),
                  ],
                ),
                error: (error, _) => Text(appErrorMessage(l10n, error)),
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _restoring ? null : _restore,
                child: Text(
                  _restoring ? l10n.t('restoring') : l10n.t('restorePurchases'),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: kIsWeb || _openingCustomerCenter
                    ? null
                    : _openCustomerCenter,
                child: Text(
                  _openingCustomerCenter
                      ? l10n.t('openingCustomerCenter')
                      : l10n.t('openCustomerCenter'),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!),
              ],
            ],
          ),
          error: (error, _) =>
              Center(child: Text(appErrorMessage(l10n, error))),
          loading: () => const AppLoadingSkeleton(lineCount: 8),
        ),
      ),
    );
  }
}
