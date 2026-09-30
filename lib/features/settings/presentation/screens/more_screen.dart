import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/theme_provider.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/core/widgets/resource_directory_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The "More" tab: profile summary, upgrade CTA, resources, appearance controls
/// (dark mode + language) and links into the full settings surfaces.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final themeMode = ref.watch(themeControllerProvider);
    final locale = ref.watch(localeControllerProvider);
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && platformDark);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            Text(
              l10n.t('settings'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: t.text,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Avatar(label: l10n.t('siteEngineer'), size: 56),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('profile'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    Text(
                      l10n.t('siteEngineer'),
                      style: TextStyle(fontSize: 13, color: t.textMuted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            _UpgradeCard(
              title: l10n.t('upgradePro'),
              subtitle: l10n.t('proSub'),
              onTap: () => context.push(AppRoutes.subscriptionPlans),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
              child: Text(
                l10n.t('resources').toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: t.textMuted,
                ),
              ),
            ),
            const ResourceDirectoryLinks(),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
              child: Text(
                l10n.t('appearance').toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: t.textFaint,
                ),
              ),
            ),
            BuildCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _RowIcon(icon: Icons.dark_mode_outlined),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            l10n.t('darkMode'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                        ),
                        Switch(
                          key: const Key('qa_more_dark_toggle'),
                          value: isDark,
                          onChanged: (v) => ref
                              .read(themeControllerProvider.notifier)
                              .setDark(v),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: t.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        _RowIcon(icon: Icons.translate),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            l10n.t('language'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                        ),
                        SegmentedToggle<String>(
                          value: locale.languageCode,
                          onChanged: (code) => ref
                              .read(localeControllerProvider.notifier)
                              .setLocale(Locale(code)),
                          options: const [
                            SegmentedOption(value: 'en', label: 'EN'),
                            SegmentedOption(value: 'ar', label: 'ع'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            BuildCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _MoreRow(
                    icon: Icons.person_outline,
                    label: l10n.t('account'),
                    onTap: () => context.push(AppRoutes.profileEdit),
                  ),
                  Divider(height: 1, color: t.border),
                  _MoreRow(
                    icon: Icons.settings_outlined,
                    label: l10n.t('settings'),
                    onTap: () => context.push(AppRoutes.settings),
                  ),
                  Divider(height: 1, color: t.border),
                  _MoreRow(
                    icon: Icons.receipt_long_outlined,
                    label: l10n.t('plan'),
                    onTap: () => context.push(AppRoutes.subscriptionManage),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.accent,
      borderRadius: BorderRadius.circular(t.rLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.rLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.workspace_premium, size: 30, color: t.onAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: t.onAccent,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: t.onAccent.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 22, color: t.onAccent),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: t.accent),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _RowIcon(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 22, color: t.textFaint),
          ],
        ),
      ),
    );
  }
}
