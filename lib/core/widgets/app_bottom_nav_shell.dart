import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/widgets/build_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppBottomNavShell extends ConsumerWidget {
  const AppBottomNavShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final isOffline = ref.watch(isOfflineProvider);
    final currentIndex = navigationShell.currentIndex;
    final isHome = currentIndex == 0;

    return PopScope(
      canPop: isHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !isHome) {
          navigationShell.goBranch(0);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: navigationShell),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !isOffline,
                child: AnimatedSlide(
                  key: const Key('offline_banner_overlay'),
                  offset: isOffline ? Offset.zero : const Offset(0, -1),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: isOffline ? 1 : 0,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    child: Material(
                      color: t.warning,
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              l10n.t('noInternetConnection'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: BuildBottomNav(
          currentIndex: currentIndex,
          addKey: const Key('qa_nav_add'),
          onAdd: () {
            ref.read(appPrefetcherProvider).warmAddEntry();
            showAddSheet(context);
          },
          onSelect: (index) {
            final prefetcher = ref.read(appPrefetcherProvider);
            switch (index) {
              case 0:
                prefetcher.warmDashboard();
              case 1:
                prefetcher.warmProjects();
            }
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
          items: [
            BuildNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              label: l10n.t('home'),
              key: const Key('qa_nav_home'),
            ),
            BuildNavItem(
              icon: Icons.apartment_outlined,
              activeIcon: Icons.apartment,
              label: l10n.t('projects'),
              key: const Key('qa_nav_projects'),
            ),
            BuildNavItem(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long,
              label: l10n.t('activity'),
              key: const Key('qa_nav_activity'),
            ),
            BuildNavItem(
              icon: Icons.menu,
              activeIcon: Icons.menu,
              label: l10n.t('more'),
              key: const Key('qa_nav_more'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet asking what to add: expense, payment, or voice entry.
Future<void> showAddSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final t = context.tokens;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.surface,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: t.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.t('whatToAdd'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.text,
              ),
            ),
            const SizedBox(height: 16),
            _AddOption(
              icon: Icons.north_east,
              color: t.expense,
              bg: t.expenseSoft,
              title: l10n.t('addExpense'),
              subtitle: l10n.t('expenseDesc'),
              route: AppRoutes.addExpense,
            ),
            const SizedBox(height: 12),
            _AddOption(
              icon: Icons.south_west,
              color: t.income,
              bg: t.incomeSoft,
              title: l10n.t('addPayment'),
              subtitle: l10n.t('paymentDesc'),
              route: AppRoutes.addPayment,
            ),
            const SizedBox(height: 14),
            Material(
              color: t.accentSoft,
              borderRadius: BorderRadius.circular(t.rMd),
              child: InkWell(
                borderRadius: BorderRadius.circular(t.rMd),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push(AppRoutes.voiceExpense);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic, size: 20, color: t.accent),
                      const SizedBox(width: 8),
                      Text(
                        l10n.t('startVoice'),
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: t.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surface2,
      borderRadius: BorderRadius.circular(t.rLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.rLg),
        onTap: () {
          Navigator.of(context).pop();
          context.push(route);
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.rLg),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12.5, color: t.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 22, color: t.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
