import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Text(
                  l10n.t('settings'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.textDark,
                      ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),
                  _SettingsCard(
                    icon: Icons.language_rounded,
                    title: l10n.t('language'),
                    subtitle: l10n.localeName(locale.languageCode),
                    color: AppColors.constructionOrange,
                    child: SegmentedButton<Locale>(
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(value: Locale('ar'), label: Text('AR')),
                        ButtonSegment(value: Locale('en'), label: Text('EN')),
                      ],
                      selected: {locale},
                      onSelectionChanged: (value) {
                        HapticFeedback.lightImpact();
                        ref
                            .read(localeControllerProvider.notifier)
                            .setLocale(value.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    icon: Icons.currency_exchange_rounded,
                    title: l10n.t('currency'),
                    subtitle: currency,
                    color: AppColors.success,
                    child: DropdownButton<String>(
                      value: currency,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      borderRadius: BorderRadius.circular(12),
                      items: const [
                        DropdownMenuItem(value: 'EGP', child: Text('EGP')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                        DropdownMenuItem(value: 'AED', child: Text('AED')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          HapticFeedback.lightImpact();
                          ref.read(selectedCurrencyProvider.notifier).state =
                              value;
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    icon: Icons.notifications_outlined,
                    title: l10n.t('notifications'),
                    subtitle: l10n.t('riskAlerts'),
                    color: AppColors.warning,
                    child: Switch.adaptive(
                      value: notificationsEnabled,
                      onChanged: (value) {
                        HapticFeedback.lightImpact();
                        ref.read(notificationsEnabledProvider.notifier).state =
                            value;
                      },
                      activeColor: AppColors.constructionOrange,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionHeader(title: l10n.t('subscription')),
                  const SizedBox(height: 8),
                  subscriptionAsync.when(
                    data: (sub) => _SubscriptionCard(
                      l10n: l10n,
                      sub: sub,
                      onUpgrade: () {
                        HapticFeedback.lightImpact();
                        context.push(AppRoutes.subscriptionPlans);
                      },
                      onManage: () {
                        HapticFeedback.lightImpact();
                        context.push(AppRoutes.subscriptionManage);
                      },
                    ),
                    error: (e, _) => _ErrorCard(message: e.toString()),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _LogoutButton(
                    label: l10n.t('logout'),
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      await ref.read(googleAuthServiceProvider).signOut();
                      await ref.read(firebaseAuthProvider).signOut();
                      ref.read(activeWorkspaceIdProvider.notifier).state = null;
                      ref.read(activeUserIdProvider.notifier).state = null;
                      if (context.mounted) {
                        context.go(AppRoutes.login);
                      }
                    },
                  ),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textBody,
            letterSpacing: 0.5,
          ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textBody,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.l10n,
    required this.sub,
    required this.onUpgrade,
    required this.onManage,
  });

  final AppLocalizations l10n;
  final dynamic sub;
  final VoidCallback onUpgrade;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final isPro = sub.tier == PlanTier.pro;
    final planLabel = isPro
        ? '${l10n.t('proPlan')} (${l10n.subscriptionStatusLabel(sub.status.name)})'
        : l10n.t('freePlan');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isPro ? AppColors.success : AppColors.constructionOrange)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: isPro ? AppColors.success : AppColors.constructionOrange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('planAndBilling'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        planLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textBody,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isPro == false)
            _SubscriptionActionTile(
              title: l10n.t('upgradeToPro'),
              onTap: onUpgrade,
              isLast: false,
            ),
          _SubscriptionActionTile(
            title: l10n.t('manageSubscription'),
            onTap: onManage,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _SubscriptionActionTile extends StatelessWidget {
  const _SubscriptionActionTile({
    required this.title,
    required this.onTap,
    this.isLast = true,
  });

  final String title;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(16))
            : BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.borderGrey),
            ),
          ),
          child: Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDark,
                    ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textBody.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
            color: AppColors.dangerLight.withValues(alpha: 0.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: AppColors.danger, size: 22),
              const SizedBox(width: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
