import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppBottomNavShell extends ConsumerStatefulWidget {
  const AppBottomNavShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppBottomNavShell> createState() => _AppBottomNavShellState();
}

class _AppBottomNavShellState extends ConsumerState<AppBottomNavShell>
    with SingleTickerProviderStateMixin {
  bool _speedDialOpen = false;
  late AnimationController _animController;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _anim = CurvedAnimation(parent: _animController, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _openDial() {
    HapticFeedback.lightImpact();
    setState(() => _speedDialOpen = true);
    _animController.forward();
  }

  void _closeDial() {
    _animController.reverse().then((_) {
      if (mounted) setState(() => _speedDialOpen = false);
    });
  }

  void _onDestinationSelected(int index) {
    if (index == 1) {
      if (_speedDialOpen) {
        _closeDial();
      } else {
        _openDial();
      }
      return;
    }
    if (_speedDialOpen) _closeDial();
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _navigateFrom(String route) {
    _closeDial();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) context.push(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isOffline = ref.watch(isOfflineProvider);
    final mq = MediaQuery.of(context);
    // Bottom nav height (NavigationBar) is roughly 80 logical pixels
    const navBarHeight = 80.0;

    return PopScope(
      canPop: !_speedDialOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _speedDialOpen) _closeDial();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Main content
            Column(
              children: [
                if (isOffline)
                  Material(
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
                Expanded(child: widget.navigationShell),
              ],
            ),

            // Speed dial overlay
            if (_speedDialOpen)
              FadeTransition(
                opacity: _animController,
                child: GestureDetector(
                  onTap: _closeDial,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    color: Colors.black54,
                  ),
                ),
              ),

            if (_speedDialOpen)
              Positioned(
                bottom: navBarHeight + mq.padding.bottom + 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top row: Worker | Voice
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DialItem(
                            animation: _anim,
                            slideOffset: const Offset(-0.5, 0.6),
                            icon: Icons.person_add_outlined,
                            label: l10n.t('addWorkerEntry'),
                            color: AppColors.constructionOrange,
                            onTap: () => _navigateFrom('${AppRoutes.addEntry}?tab=1'),
                          ),
                          const SizedBox(width: 20),
                          _DialItem(
                            animation: _anim,
                            slideOffset: const Offset(0.5, 0.6),
                            icon: Icons.mic_outlined,
                            label: l10n.t('voiceExpense'),
                            color: const Color(0xFF7C3AED),
                            onTap: () => _navigateFrom(AppRoutes.voiceExpense),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Bottom row: Expenses | Payment
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DialItem(
                            animation: _anim,
                            slideOffset: const Offset(-0.3, 0.4),
                            icon: Icons.receipt_long_outlined,
                            label: l10n.t('addExpense'),
                            color: AppColors.danger,
                            onTap: () => _navigateFrom('${AppRoutes.addEntry}?tab=0'),
                          ),
                          const SizedBox(width: 20),
                          _DialItem(
                            animation: _anim,
                            slideOffset: const Offset(0.3, 0.4),
                            icon: Icons.payments_outlined,
                            label: l10n.t('addPayment'),
                            color: AppColors.success,
                            onTap: () => _navigateFrom(AppRoutes.addPayment),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: widget.navigationShell.currentIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined, key: Key('qa_nav_home')),
              selectedIcon: const Icon(Icons.home, key: Key('qa_nav_home')),
              label: l10n.t('home'),
            ),
            NavigationDestination(
              icon: AnimatedContainer(
                key: const Key('qa_nav_add'),
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _speedDialOpen
                      ? AppColors.textDark
                      : AppColors.constructionOrange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_speedDialOpen
                              ? AppColors.textDark
                              : AppColors.constructionOrange)
                          .withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: AnimatedRotation(
                  turns: _speedDialOpen ? 0.125 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(
                    Icons.add,
                    color: AppColors.surfaceSolid,
                    size: 28,
                  ),
                ),
              ),
              label: l10n.t('add'),
            ),
            NavigationDestination(
              icon: const Icon(
                Icons.work_outline,
                key: Key('qa_nav_projects'),
              ),
              selectedIcon: const Icon(
                Icons.work,
                key: Key('qa_nav_projects'),
              ),
              label: l10n.t('projects'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialItem extends StatelessWidget {
  const _DialItem({
    required this.animation,
    required this.slideOffset,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Animation<double> animation;
  final Offset slideOffset;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(begin: slideOffset, end: Offset.zero)
          .animate(animation),
      child: FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: animation,
          child: GestureDetector(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
