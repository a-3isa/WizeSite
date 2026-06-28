import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/safe_external_url.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/core/widgets/section_header.dart';
import 'package:buildtrack_app/core/widgets/usage_card.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _currencyOverride;
  bool? _riskAlertsOverride;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    final settingsAsync = ref.watch(currentUserSettingsProvider);
    final userId = ref.watch(activeUserIdProvider);
    final persistedCurrency = settingsAsync.value?.defaultCurrency ?? 'EGP';
    final persistedNotifications =
        settingsAsync.value?.riskAlertsEnabled ?? true;
    final currency = _currencyOverride ?? persistedCurrency;
    final notificationsEnabled = _riskAlertsOverride ?? persistedNotifications;
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
                    SectionHeader(title: l10n.t('settingsPreferences')),
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
                            DropdownMenuEntry(value: 'KWD', label: 'KWD'),
                            DropdownMenuEntry(value: 'QAR', label: 'QAR'),
                            DropdownMenuEntry(value: 'BHD', label: 'BHD'),
                            DropdownMenuEntry(value: 'OMR', label: 'OMR'),
                            DropdownMenuEntry(value: 'JOD', label: 'JOD'),
                          ],
                          onSelected: (value) => _saveCurrency(
                            userId: userId,
                            previous: persistedCurrency,
                            next: value,
                          ),
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
                        onChanged: (value) => _saveRiskAlerts(
                          userId: userId,
                          previous: persistedNotifications,
                          next: value,
                        ),
                        activeThumbColor: AppColors.constructionOrange,
                        activeTrackColor: AppColors.constructionOrange,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SectionHeader(title: l10n.t('settingsWorkspace')),
                    const SizedBox(height: 8),
                    _WorkspaceSettingsCard(prefetcher: prefetcher),
                    const SizedBox(height: 8),
                    _SettingsCard(
                      icon: Icons.sync_rounded,
                      title: l10n.t('syncStatus'),
                      subtitle: l10n.t('syncStatusSubtitle'),
                      color: AppColors.constructionOrange,
                      onTap: () {
                        prefetcher.warmSettings();
                        context.push(AppRoutes.syncStatus);
                      },
                      child: IconButton(
                        onPressed: () {
                          prefetcher.warmSettings();
                          context.push(AppRoutes.syncStatus);
                        },
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SectionHeader(title: l10n.t('subscription')),
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
                    SectionHeader(title: l10n.t('aboutApp')),
                    const SizedBox(height: 8),
                    _AboutAndLegalSection(l10n: l10n),
                    const SizedBox(height: 24),
                    if (kDebugMode ||
                        const bool.fromEnvironment(
                          'SHOW_CRASHLYTICS_TEST',
                        )) ...[
                      SectionHeader(title: l10n.t('crashlyticsDiagnostics')),
                      const SizedBox(height: 8),
                      _CrashlyticsTestCard(l10n: l10n),
                      const SizedBox(height: 24),
                    ],
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

  Future<void> _saveCurrency({
    required String? userId,
    required String previous,
    required String? next,
  }) async {
    if (next == null || next == previous) {
      return;
    }
    HapticFeedback.lightImpact();
    if (userId == null || userId.isEmpty) {
      return;
    }
    setState(() => _currencyOverride = next);
    try {
      await ref
          .read(userSettingsRepositoryProvider)
          .updateCurrency(userId, next);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _currencyOverride = null);
      _showSettingsSaveFailed();
    }
  }

  Future<void> _saveRiskAlerts({
    required String? userId,
    required bool previous,
    required bool next,
  }) async {
    HapticFeedback.lightImpact();
    if (userId == null || userId.isEmpty) {
      return;
    }
    setState(() => _riskAlertsOverride = next);
    try {
      await ref
          .read(userSettingsRepositoryProvider)
          .updateRiskAlerts(userId, next);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _riskAlertsOverride = previous);
      _showSettingsSaveFailed();
    }
  }

  void _showSettingsSaveFailed() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.t('settingsSaveFailed'))));
  }
}

class _WorkspaceSettingsCard extends ConsumerWidget {
  const _WorkspaceSettingsCard({required this.prefetcher});

  final AppPrefetcher prefetcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final summaries =
        ref.watch(userWorkspaceSummariesProvider).value ??
        const <WorkspaceSummary>[];
    WorkspaceSummary? current;
    for (final summary in summaries) {
      if (summary.id == activeId) {
        current = summary;
        break;
      }
    }
    final name = current?.name ?? '';

    return _SettingsCard(
      icon: Icons.business_outlined,
      title: l10n.t('settingsWorkspace'),
      subtitle: name.isEmpty ? l10n.t('settingsWorkspace') : name,
      color: AppColors.constructionOrange,
      onTap: () {
        prefetcher.warmSettings();
        context.push(AppRoutes.workspaceSettings);
      },
      child: IconButton(
        onPressed: () {
          prefetcher.warmSettings();
          context.push(AppRoutes.workspaceSettings);
        },
        icon: const Icon(Icons.chevron_right_rounded),
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
    final usageAsync = ref.watch(currentUsageProvider);
    final cachedSub = subscriptionAsync.value;
    if (cachedSub != null) {
      return Column(
        children: [
          _SubscriptionCard(
            l10n: l10n,
            sub: cachedSub,
            onUpgrade: onUpgrade,
            onManage: onManage,
          ),
          const SizedBox(height: 12),
          usageAsync.whenStale(
            data: (usage) => UsageCard(usage: usage),
            error: (_, _) => const SizedBox.shrink(),
            loading: () => const AppLoadingSkeleton(
              lineCount: 3,
              padding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          if (subscriptionAsync.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      );
    }
    return subscriptionAsync.whenStale(
      data: (sub) => Column(
        children: [
          _SubscriptionCard(
            l10n: l10n,
            sub: sub,
            onUpgrade: onUpgrade,
            onManage: onManage,
          ),
          const SizedBox(height: 12),
          usageAsync.whenStale(
            data: (usage) => UsageCard(usage: usage),
            error: (_, _) => const SizedBox.shrink(),
            loading: () => const AppLoadingSkeleton(
              lineCount: 3,
              padding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
      error: (e, _) => AppRecoverableError(message: appErrorMessage(l10n, e)),
      loading: () => const _SubscriptionLoadingCard(),
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
        ),
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
                        isPro
                            ? AppColors.success
                            : AppColors.constructionOrange,
                        (isPro
                                ? AppColors.success
                                : AppColors.constructionOrange)
                            .withValues(alpha: 0.78),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isPro
                                    ? AppColors.success
                                    : AppColors.constructionOrange)
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

class _AboutAndLegalSection extends StatelessWidget {
  const _AboutAndLegalSection({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
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
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              final version = info == null
                  ? l10n.t('loading')
                  : '${info.version} (${info.buildNumber})';
              return _SettingsLinkTile(
                title: l10n.t('appVersion'),
                subtitle: version,
                icon: Icons.info_outline_rounded,
                isLast: false,
              );
            },
          ),
          _SettingsLinkTile(
            title: l10n.t('helpAndSupport'),
            subtitle: 'support@buildozer.app',
            icon: Icons.help_outline_rounded,
            url: 'mailto:support@buildozer.app',
            isLast: false,
          ),
          _SettingsLinkTile(
            title: l10n.t('privacyPolicy'),
            subtitle: 'buildozer.app/privacy',
            icon: Icons.privacy_tip_outlined,
            url: 'https://buildozer.app/privacy',
            isLast: false,
          ),
          _SettingsLinkTile(
            title: l10n.t('termsOfService'),
            subtitle: 'buildozer.app/terms',
            icon: Icons.description_outlined,
            url: 'https://buildozer.app/terms',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _SettingsLinkTile extends StatelessWidget {
  const _SettingsLinkTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isLast,
    this.url,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isLast;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final canOpen = url != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canOpen ? () => launchSafeExternalUrl(url) : null,
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(16))
            : BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: isLast
              ? null
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderGrey),
                  ),
                ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textBody, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                    ),
                  ],
                ),
              ),
              if (canOpen)
                Icon(
                  Icons.open_in_new_rounded,
                  color: AppColors.textBody.withValues(alpha: 0.6),
                  size: 18,
                ),
            ],
          ),
        ),
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

class _ProfileSection extends ConsumerWidget {
  const _ProfileSection({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(firebaseAuthProvider).currentUser;
    final settings = ref.watch(currentUserSettingsProvider).value;
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

class _CrashlyticsTestCard extends StatefulWidget {
  const _CrashlyticsTestCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_CrashlyticsTestCard> createState() => _CrashlyticsTestCardState();
}

class _CrashlyticsTestCardState extends State<_CrashlyticsTestCard> {
  bool _sent = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          _DebugTile(
            label: widget.l10n.t('runDiagnostics'),
            onTap: () => _confirmDiagnostics(context),
            isLast: false,
          ),
          _DebugTile(
            label: _sent
                ? widget.l10n.t('crashlyticsNonFatalSent')
                : widget.l10n.t('sendTestNonFatalError'),
            onTap: _sent ? null : _sendNonFatal,
            isLast: false,
          ),
          _DebugTile(
            label: widget.l10n.t('forceCrashKillsApp'),
            isDestructive: true,
            onTap: () => _confirmCrash(context),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Future<void> _sendNonFatal() async {
    await FirebaseCrashlytics.instance.recordError(
      Exception('Crashlytics test non-fatal error'),
      StackTrace.current,
      reason: 'debug.crashlytics_test',
    );
    await FirebaseCrashlytics.instance.sendUnsentReports();
    if (mounted) {
      setState(() => _sent = true);
    }
  }

  Future<void> _confirmDiagnostics(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.l10n.t('runDiagnosticsConfirmTitle')),
        content: Text(widget.l10n.t('runDiagnosticsConfirmMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.l10n.t('runDiagnostics')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _sendNonFatal();
    }
  }

  Future<void> _confirmCrash(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.l10n.t('forceCrashConfirmTitle')),
        content: Text(widget.l10n.t('forceCrashConfirmMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.l10n.t('forceCrash')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      FirebaseCrashlytics.instance.crash();
    }
  }
}

class _DebugTile extends StatelessWidget {
  const _DebugTile({
    required this.label,
    required this.onTap,
    required this.isLast,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isLast;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.danger : AppColors.textDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(16))
            : BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: isLast
              ? null
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderGrey),
                  ),
                ),
          child: Row(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: onTap == null
                      ? AppColors.textBody.withValues(alpha: 0.5)
                      : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
