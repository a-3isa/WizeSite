import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final selectedCurrencyProvider = StateProvider<String>((ref) => 'EGP');
final notificationsEnabledProvider = StateProvider<bool>((ref) => true);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    final currency = ref.watch(selectedCurrencyProvider);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);
    final subscriptionAsync = ref.watch(currentSubscriptionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(l10n.t('language')),
              subtitle: Text(
                locale.languageCode == 'ar' ? 'العربية' : 'English',
              ),
              trailing: SegmentedButton<Locale>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: Locale('ar'), label: Text('AR')),
                  ButtonSegment(value: Locale('en'), label: Text('EN')),
                ],
                selected: {locale},
                onSelectionChanged: (value) {
                  ref
                      .read(localeControllerProvider.notifier)
                      .setLocale(value.first);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.attach_money),
              title: Text(l10n.t('currency')),
              subtitle: Text(currency),
              trailing: DropdownButton<String>(
                value: currency,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'EGP', child: Text('EGP')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                  DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                  DropdownMenuItem(value: 'AED', child: Text('AED')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref.read(selectedCurrencyProvider.notifier).state = value;
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: Text(l10n.t('notifications')),
              subtitle: Text(l10n.t('riskAlerts')),
              value: notificationsEnabled,
              onChanged: (value) {
                ref.read(notificationsEnabledProvider.notifier).state = value;
              },
            ),
          ),
          const SizedBox(height: 8),
          subscriptionAsync.when(
            data: (sub) => Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.workspace_premium),
                    title: Text(l10n.t('planAndBilling')),
                    subtitle: Text(
                      sub.tier == PlanTier.pro
                          ? '${l10n.t('proPlan')} (${sub.status.name})'
                          : l10n.t('freePlan'),
                    ),
                  ),
                  if (sub.tier == PlanTier.free)
                    ListTile(
                      title: Text(l10n.t('upgradeToPro')),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => context.push(AppRoutes.subscriptionPlans),
                    ),
                  ListTile(
                    title: Text(l10n.t('manageSubscription')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => context.push(AppRoutes.subscriptionManage),
                  ),
                ],
              ),
            ),
            error: (e, _) => Text(e.toString()),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l10n.t('logout')),
              onTap: () async {
                await ref.read(googleAuthServiceProvider).signOut();
                await ref.read(firebaseAuthProvider).signOut();
                ref.read(activeWorkspaceIdProvider.notifier).state = null;
                ref.read(activeUserIdProvider.notifier).state = null;
                if (context.mounted) {
                  context.go(AppRoutes.login);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
