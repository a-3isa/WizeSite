import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/features/subscription/domain/purchase_coordinator.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LimitReachedScreen extends ConsumerStatefulWidget {
  const LimitReachedScreen({required this.limitType, super.key});

  final String limitType;

  @override
  ConsumerState<LimitReachedScreen> createState() => _LimitReachedScreenState();
}

class _LimitReachedScreenState extends ConsumerState<LimitReachedScreen> {
  bool _loading = false;
  String? _message;

  String _title() {
    switch (widget.limitType) {
      case 'activeProjects':
        return 'Active Project Limit Reached';
      case 'expensesPerMonth':
        return 'Monthly Expense Limit Reached';
      case 'paymentsPerMonth':
        return 'Monthly Payment Limit Reached';
      case 'workerEntriesPerMonth':
        return 'Monthly Worker Entry Limit Reached';
      case 'teamMembers':
        return 'Team Member Limit Reached';
      default:
        return 'Usage Limit Reached';
    }
  }

  Future<void> _upgrade() async {
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
          setState(() => _message = 'Purchase was cancelled.');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade Required')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                _title(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'You are on the Free plan with strict usage limits. Upgrade to Pro to continue this action.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loading ? null : _upgrade,
                icon: const Icon(Icons.workspace_premium),
                label: Text(_loading ? 'Loading...' : 'Upgrade to Pro'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!),
              ],
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Maybe later'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
