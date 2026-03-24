import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  String? _statusMessage;
  List<OfferingPackage> _packages = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final workspaceId = ref.read(activeWorkspaceIdProvider);
      final coordinator = ref.read(purchaseCoordinatorProvider);
      await coordinator.configure(appUserId: workspaceId ?? 'guest-workspace');
      final packages = await coordinator.getPackages();
      setState(() {
        _packages = packages.isEmpty
            ? const [
                OfferingPackage(
                  id: 'monthly',
                  title: 'WizeSite Pro Monthly',
                  priceString: '\$9.99',
                  periodLabel: 'monthly',
                  productCode: 'monthly',
                  offeringId: 'default',
                ),
                OfferingPackage(
                  id: 'yearly',
                  title: 'WizeSite Pro Yearly',
                  priceString: '\$89.99',
                  periodLabel: 'yearly',
                  productCode: 'yearly',
                  offeringId: 'default',
                ),
                OfferingPackage(
                  id: 'lifetime',
                  title: 'WizeSite Pro Lifetime',
                  priceString: '\$249.99',
                  periodLabel: 'lifetime',
                  productCode: 'lifetime',
                  offeringId: 'default',
                ),
              ]
            : packages;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openPaywall() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _purchasing = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final result = await ref
          .read(purchaseCoordinatorProvider)
          .presentPaywallIfNeeded();
      if (!mounted) {
        return;
      }
      switch (result) {
        case PaywallPresentationResult.purchased:
        case PaywallPresentationResult.restored:
        case PaywallPresentationResult.notPresented:
          context.go(AppRoutes.subscriptionSuccess);
          break;
        case PaywallPresentationResult.cancelled:
          setState(() => _statusMessage = l10n.t('purchaseCancelled'));
          break;
        case PaywallPresentationResult.notSupported:
          setState(() => _statusMessage = l10n.t('nativePaywallNotSupported'));
          break;
        case PaywallPresentationResult.error:
          setState(() => _error = l10n.t('paywallFailed'));
          break;
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _purchasing = false);
      }
    }
  }

  Future<void> _purchase(OfferingPackage package) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _purchasing = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final ok = await ref
          .read(purchaseCoordinatorProvider)
          .purchase(package.id);
      if (ok && mounted) {
        context.go(AppRoutes.subscriptionSuccess);
      } else if (!ok) {
        setState(() => _statusMessage = l10n.t('purchaseNotCompleted'));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _purchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBackScope(
      fallbackRoute: AppRoutes.settings,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('subscription'),
          fallbackRoute: AppRoutes.settings,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: const Color(0xFFFFF4E8),
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome),
                      title: Text(l10n.t('proPlan')),
                      subtitle: Text(l10n.t('proUnlocksSubtitle')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.timer),
                      title: Text(l10n.t('freeTrial')),
                      subtitle: Text(l10n.t('trialStartsWithPurchase')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _purchasing ? null : _openPaywall,
                    icon: const Icon(Icons.workspace_premium),
                    label: Text(
                      _purchasing
                          ? l10n.t('loading')
                          : l10n.t('continueWithPaywall'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final package in _packages)
                    Card(
                      child: ListTile(
                        title: Text(package.title),
                        subtitle: Text(
                          '${package.priceString} / ${package.periodLabel}',
                        ),
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text(
                            package.productCode.substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        trailing: FilledButton(
                          onPressed: _purchasing
                              ? null
                              : () => _purchase(package),
                          child: Text(
                            _purchasing
                                ? l10n.t('loadingShort')
                                : l10n.t('continue'),
                          ),
                        ),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(_statusMessage!),
                  ],
                ],
              ),
      ),
    );
  }
}
