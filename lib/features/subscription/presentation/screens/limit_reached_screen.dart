import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LimitReachedScreen extends ConsumerStatefulWidget {
  const LimitReachedScreen({
    required this.limitType,
    this.current,
    this.max,
    super.key,
  });

  final String limitType;
  final int? current;
  final int? max;

  @override
  ConsumerState<LimitReachedScreen> createState() => _LimitReachedScreenState();
}

class _LimitReachedScreenState extends ConsumerState<LimitReachedScreen> {
  bool _loading = false;
  String? _message;

  Future<void> _upgrade() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await ref.read(revenueCatBootstrapProvider.future);
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
        case PaywallPresentationResult.notSupported:
          context.push(AppRoutes.subscriptionPlans);
          break;
        case PaywallPresentationResult.cancelled:
          setState(() => _message = l10n.t('purchaseCancelled'));
          break;
        case PaywallPresentationResult.error:
          context.push(AppRoutes.subscriptionPlans);
          break;
      }
    } catch (_) {
      if (mounted) {
        context.push(AppRoutes.subscriptionPlans);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBackScope(
      fallbackRoute: AppRoutes.dashboard,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('upgradeRequired'),
          fallbackRoute: AppRoutes.dashboard,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  l10n.limitTitle(widget.limitType),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.limitMessage(
                    widget.limitType,
                    current: widget.current,
                    max: widget.max,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loading ? null : _upgrade,
                  icon: const Icon(Icons.workspace_premium),
                  label: Text(
                    _loading ? l10n.t('loading') : l10n.t('upgradeToPro'),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!),
                ],
                TextButton(
                  onPressed: () => appNavigateBack(
                    context,
                    fallbackRoute: AppRoutes.dashboard,
                  ),
                  child: Text(l10n.t('maybeLater')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
