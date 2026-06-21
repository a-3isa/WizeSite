import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppBottomNavShell extends ConsumerWidget {
  const AppBottomNavShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isOffline = ref.watch(isOfflineProvider);
    final isHome = navigationShell.currentIndex == 0;

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
                      color: AppColors.warning,
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
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            final prefetcher = ref.read(appPrefetcherProvider);
            switch (index) {
              case 0:
                prefetcher.warmDashboard();
              case 1:
                prefetcher.warmAddEntry();
              case 2:
                prefetcher.warmReports();
              case 3:
                prefetcher.warmProjects();
            }
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined, key: Key('qa_nav_home')),
              selectedIcon: const Icon(Icons.home, key: Key('qa_nav_home')),
              label: l10n.t('home'),
            ),
            NavigationDestination(
              icon: const Icon(
                Icons.add_circle_outline,
                key: Key('qa_nav_add'),
              ),
              selectedIcon: const Icon(
                Icons.add_circle,
                key: Key('qa_nav_add'),
              ),
              label: l10n.t('add'),
            ),
            NavigationDestination(
              icon: const Icon(
                Icons.assessment_outlined,
                key: Key('qa_nav_reports'),
              ),
              selectedIcon: const Icon(
                Icons.assessment,
                key: Key('qa_nav_reports'),
              ),
              label: l10n.t('reports'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.work_outline, key: Key('qa_nav_projects')),
              selectedIcon: const Icon(Icons.work, key: Key('qa_nav_projects')),
              label: l10n.t('projects'),
            ),
          ],
        ),
      ),
    );
  }
}
