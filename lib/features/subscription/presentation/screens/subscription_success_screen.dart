import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SubscriptionSuccessScreen extends StatelessWidget {
  const SubscriptionSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 72, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                l10n.t('subscriptionActivated'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.t('subscriptionActivatedSubtitle'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go(AppRoutes.dashboard),
                child: Text(l10n.t('goToDashboard')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
