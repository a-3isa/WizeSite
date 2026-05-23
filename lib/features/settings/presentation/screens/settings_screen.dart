import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    final settingsAsync = ref.watch(currentUserSettingsProvider);
    final userId = ref.watch(activeUserIdProvider);
    final currency = settingsAsync.valueOrNull?.defaultCurrency ?? 'EGP';
    final notificationsEnabled =
        settingsAsync.valueOrNull?.riskAlertsEnabled ?? true;
    final prefetcher = ref.read(appPrefetcherProvider);

    return AppBackScope(
      fallbackRoute: AppRoutes.dashboard,
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Row(
                    children: [
                      const AppBackButton(fallbackRoute: AppRoutes.dashboard),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.t('settings'),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: AppColors.textDark,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _ProfileSection(l10n: l10n),
                    const SizedBox(height: 24),
                    _SectionHeader(title: l10n.t('settings')),
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
                            const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
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
                      child: SizedBox(
                        width: 130,
                        child: BelowDropdownField<String>(
                          label: l10n.t('currency'),
                          value: currency,
                          entries: const [
                            DropdownMenuEntry(value: 'EGP', label: 'EGP'),
                            DropdownMenuEntry(value: 'USD', label: 'USD'),
                            DropdownMenuEntry(value: 'SAR', label: 'SAR'),
                            DropdownMenuEntry(value: 'AED', label: 'AED'),
                          ],
                          onSelected: (value) {
                            if (value != null) {
                              HapticFeedback.lightImpact();
                              if (userId == null || userId.isEmpty) {
                                return;
                              }
                              ref
                                  .read(userSettingsRepositoryProvider)
                                  .updateCurrency(userId, value)
                                  .catchError((error) {
                                    if (!context.mounted) {
                                      return;
                                    }
                                    // ScaffoldMessenger.of(context).showSnackBar(
                                    //   SnackBar(content: Text(error.toString())),
                                    // );
                                  });
                            }
                          },
                        ),
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
                        onChanged: (value) async {
                          HapticFeedback.lightImpact();
                          if (userId == null || userId.isEmpty) {
                            return;
                          }
                          try {
                            await ref
                                .read(userSettingsRepositoryProvider)
                                .updateRiskAlerts(userId, value);
                          } catch (error) {
                            if (!context.mounted) {
                              return;
                            }
                            // ScaffoldMessenger.of(context).showSnackBar(
                            //   SnackBar(content: Text(error.toString())),
                            // );
                          }
                        },
                        activeThumbColor: AppColors.constructionOrange,
                        activeTrackColor: AppColors.constructionOrange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingsCard(
                      icon: Icons.person_outline_rounded,
                      title: l10n.t('editProfile'),
                      subtitle: l10n.t('profile'),
                      color: AppColors.constructionOrange,
                      child: IconButton(
                        onPressed: () {
                          prefetcher.warmSettings();
                          context.push(AppRoutes.profileEdit);
                        },
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingsCard(
                      icon: Icons.group_outlined,
                      title: l10n.t('manageTeam'),
                      subtitle: l10n.t('teamMembersTitle'),
                      color: AppColors.success,
                      child: IconButton(
                        onPressed: () {
                          prefetcher.warmSettings();
                          context.push(AppRoutes.teamManagement);
                        },
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(title: l10n.t('subscription')),
                    const SizedBox(height: 8),
                    _SubscriptionSettingsSection(
                      l10n: l10n,
                      onUpgrade: () {
                        HapticFeedback.lightImpact();
                        prefetcher.warmSettings();
                        context.push(AppRoutes.subscriptionPlans);
                      },
                      onManage: () {
                        HapticFeedback.lightImpact();
                        prefetcher.warmSettings();
                        context.push(AppRoutes.subscriptionManage);
                      },
                    ),
                    const SizedBox(height: 24),
                    _LogoutButton(
                      label: l10n.t('logout'),
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        await ref.read(googleAuthServiceProvider).signOut();
                        await ref.read(firebaseAuthProvider).signOut();
                        ref.read(activeWorkspaceIdProvider.notifier).state =
                            null;
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
      ),
    );
  }
}

class _SubscriptionSettingsSection extends ConsumerWidget {
  const _SubscriptionSettingsSection({
    required this.l10n,
    required this.onUpgrade,
    required this.onManage,
  });

  final AppLocalizations l10n;
  final VoidCallback onUpgrade;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionAsync = ref.watch(currentSubscriptionStreamProvider);
    final cachedSub = subscriptionAsync.valueOrNull;
    if (cachedSub != null) {
      return Column(
        children: [
          _SubscriptionCard(
            l10n: l10n,
            sub: cachedSub,
            onUpgrade: onUpgrade,
            onManage: onManage,
          ),
          if (subscriptionAsync.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      );
    }
    return subscriptionAsync.when(
      data: (sub) => _SubscriptionCard(
        l10n: l10n,
        sub: sub,
        onUpgrade: onUpgrade,
        onManage: onManage,
      ),
      error: (e, _) => _ErrorCard(message: e.toString()),
      loading: () => const _SubscriptionLoadingCard(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.constructionOrange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
            letterSpacing: -0.2,
          ),
        ),
      ],
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.78)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textBody),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                    gradient: LinearGradient(
                      colors: [
                        isPro ? AppColors.success : AppColors.constructionOrange,
                        (isPro ? AppColors.success : AppColors.constructionOrange)
                            .withValues(alpha: 0.78),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (isPro ? AppColors.success : AppColors.constructionOrange)
                            .withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
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
            border: Border(top: BorderSide(color: AppColors.borderGrey)),
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
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
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

class _SubscriptionLoadingCard extends StatelessWidget {
  const _SubscriptionLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: const LinearProgressIndicator(minHeight: 2),
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

class _ProfileSection extends ConsumerWidget {
  const _ProfileSection({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(firebaseAuthProvider).currentUser;
    final settings = ref.watch(currentUserSettingsProvider).valueOrNull;
    final name = settings?.fullName.isNotEmpty == true
        ? settings!.fullName
        : user?.displayName ?? user?.email?.split('@').first ?? 'User';
    final email = settings?.email.isNotEmpty == true
        ? settings!.email
        : user?.email ?? '';
    final photoUrl = settings?.photoUrl ?? user?.photoURL ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderGrey),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.constructionOrange.withValues(alpha: 0.12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.constructionOrange.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: photoUrl.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      photoUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _ProfileAvatarFallback(label: _initials(name)),
                    ),
                  )
                : Center(child: _ProfileAvatarFallback(label: _initials(name))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textBody,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(appPrefetcherProvider).warmSettings();
              context.push(AppRoutes.profileEdit);
            },
            icon: Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textBody.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'U';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _ProfileAvatarFallback extends StatelessWidget {
  const _ProfileAvatarFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.constructionOrange, AppColors.warning],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
