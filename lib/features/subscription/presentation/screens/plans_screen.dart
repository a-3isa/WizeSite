import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
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
  bool _loadFailed = false;
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
      _loadFailed = false;
      _error = null;
      _statusMessage = null;
    });
    try {
      final workspaceId = ref.read(activeWorkspaceIdProvider);
      final coordinator = ref.read(purchaseCoordinatorProvider);
      await coordinator.configure(appUserId: workspaceId ?? 'guest-workspace');
      final packages = await coordinator.getPackages();
      setState(() {
        _packages = packages;
      });
    } catch (_) {
      setState(() {
        _packages = const [];
        _loadFailed = true;
      });
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
      setState(() => _error = appErrorMessage(l10n, e));
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
      setState(() => _error = appErrorMessage(l10n, e));
    } finally {
      if (mounted) {
        setState(() => _purchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final featureKeys = _comparisonFeatureKeys(_packages);
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
                  if (_packages.isEmpty)
                    AppRecoverableError(
                      title: l10n.t('plansUnavailableTitle'),
                      message: l10n.t('plansUnavailableMessage'),
                      retryLabel: l10n.t('retry'),
                      onRetry: _loading ? null : _load,
                    )
                  else ...[
                    for (final package in _packages)
                      _PlanPackageCard(
                        package: package,
                        purchasing: _purchasing,
                        onPurchase: () => _purchase(package),
                      ),
                    if (featureKeys.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        l10n.t('comparePlans'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (final featureKey in featureKeys)
                        _PlanFeatureComparisonRow(
                          featureLabel: _planFeatureLabel(l10n, featureKey),
                          packages: _packages,
                          featureKey: featureKey,
                        ),
                    ],
                  ],
                  if (_loadFailed && _packages.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.t('plansRecoveredAfterRetry'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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

class _PlanPackageCard extends StatelessWidget {
  const _PlanPackageCard({
    required this.package,
    required this.purchasing,
    required this.onPurchase,
  });

  final OfferingPackage package;
  final bool purchasing;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final initialSource = package.productCode.trim().isEmpty
        ? package.title.trim()
        : package.productCode.trim();
    final initial = initialSource.isEmpty ? '?' : initialSource.substring(0, 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Expanded(child: Text(package.title)),
                  if (package.isRecommended)
                    Chip(label: Text(l10n.t('planRecommended'))),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${package.priceString} / ${package.periodLabel}'),
                  if (package.savingsLabel?.trim().isNotEmpty == true)
                    Text(package.savingsLabel!),
                  if (package.trialPeriodLabel?.trim().isNotEmpty == true)
                    Text(package.trialPeriodLabel!),
                ],
              ),
              leading: CircleAvatar(
                radius: 14,
                child: Text(
                  initial.toUpperCase(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              trailing: FilledButton(
                onPressed: purchasing ? null : onPurchase,
                child: Text(
                  purchasing ? l10n.t('loadingShort') : l10n.t('continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanFeatureComparisonRow extends StatelessWidget {
  const _PlanFeatureComparisonRow({
    required this.featureLabel,
    required this.packages,
    required this.featureKey,
  });

  final String featureLabel;
  final List<OfferingPackage> packages;
  final String featureKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              featureLabel,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final package in packages)
                  Chip(
                    label: Text(
                      package.featureKeys.contains(featureKey)
                          ? l10n.t('planFeatureIncluded')
                          : l10n.t('planFeatureNotIncluded'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _comparisonFeatureKeys(List<OfferingPackage> packages) {
  final keys = <String>{};
  for (final package in packages) {
    keys.addAll(package.featureKeys);
  }
  return keys.toList(growable: false)..sort();
}

String _planFeatureLabel(AppLocalizations l10n, String featureKey) {
  switch (featureKey) {
    case 'unlimited_projects':
      return l10n.t('planFeatureUnlimitedProjects');
    case 'priority_support':
      return l10n.t('planFeaturePrioritySupport');
    case 'advanced_reports':
      return l10n.t('planFeatureAdvancedReports');
    default:
      return featureKey
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
  }
}
