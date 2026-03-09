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
    setState(() {
      _restoring = true;
      _message = null;
    });
    final ok = await ref.read(purchaseCoordinatorProvider).restore();
    setState(() {
      _restoring = false;
      _message = ok
          ? 'Purchases restored successfully.'
          : 'No active purchases found.';
    });
  }

  Future<void> _openCustomerCenter() async {
    setState(() {
      _openingCustomerCenter = true;
      _message = null;
    });
    try {
      await ref.read(purchaseCoordinatorProvider).presentCustomerCenter();
      if (mounted) {
        setState(() => _message = 'Customer Center closed.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'Customer Center failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _openingCustomerCenter = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(revenueCatBootstrapProvider);
    final subAsync = ref.watch(currentSubscriptionProvider);
    final customerInfoAsync = ref.watch(revenueCatCustomerInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Subscription')),
      body: subAsync.when(
        data: (sub) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                title: Text(sub.tier == PlanTier.pro ? 'Pro' : 'Free'),
                subtitle: Text('Status: ${sub.status.name}'),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Trial Ends At'),
                subtitle: Text(sub.trialEndsAt?.toIso8601String() ?? '-'),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Current Period Ends At'),
                subtitle: Text(sub.periodEndsAt?.toIso8601String() ?? '-'),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Store'),
                subtitle: Text(sub.store),
              ),
            ),
            customerInfoAsync.when(
              data: (info) => Column(
                children: [
                  Card(
                    child: ListTile(
                      title: const Text('RevenueCat App User ID'),
                      subtitle: Text(
                        info.appUserId.isEmpty ? '-' : info.appUserId,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('WizeSite Pro Entitlement'),
                      subtitle: Text(
                        info.hasProEntitlement ? 'Active' : 'Not active',
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('Current Product'),
                      subtitle: Text(
                        info.productIdentifier.isEmpty
                            ? '-'
                            : info.productIdentifier,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('Entitlement Expiration'),
                      subtitle: Text(
                        info.latestExpirationDate?.toIso8601String() ?? '-',
                      ),
                    ),
                  ),
                ],
              ),
              error: (error, _) => Text(error.toString()),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _restoring ? null : _restore,
              child: Text(_restoring ? 'Restoring...' : 'Restore Purchases'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: kIsWeb || _openingCustomerCenter
                  ? null
                  : _openCustomerCenter,
              child: Text(
                _openingCustomerCenter
                    ? 'Opening Customer Center...'
                    : 'Open Customer Center',
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!),
            ],
          ],
        ),
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
