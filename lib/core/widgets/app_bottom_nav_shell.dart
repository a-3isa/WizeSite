import 'dart:math' as math;

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class _DialConfig {
  const _DialConfig({
    required this.angleDeg,
    required this.icon,
    required this.label,
    required this.color,
    required this.route,
  });
  final double angleDeg; // degrees from vertical — 0 = straight up
  final IconData icon;
  final String label;
  final Color color;
  final String route;
}

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
      duration: const Duration(milliseconds: 250),
    );
    _anim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
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

    // Floating + button: centre sits at the top edge of the NavigationBar.
    // NavigationBar visual content = 80 dp; system gesture inset below.
    const navVisualHeight = 80.0;
    const buttonRadius = 30.0;
    final plusCenterFromScreenBottom = mq.padding.bottom + navVisualHeight;

    // Arc geometry — radius and angles chosen so 4 items never overlap on phones ≥ 360 dp
    const arcRadius = 148.0;
    const itemHalfW = 42.0; // half of 84 dp fixed-width item
    const itemHalfH = 47.0; // approx centre of (56 dp circle + label)

    final dialItems = [
      _DialConfig(
        angleDeg: -64,
        icon: Icons.person_add_outlined,
        label: l10n.t('addWorkerEntry'),
        color: AppColors.constructionOrange,
        route: '${AppRoutes.addEntry}?tab=1',
      ),
      _DialConfig(
        angleDeg: -22,
        icon: Icons.receipt_long_outlined,
        label: l10n.t('addExpense'),
        color: AppColors.danger,
        route: '${AppRoutes.addEntry}?tab=0',
      ),
      _DialConfig(
        angleDeg: 22,
        icon: Icons.payments_outlined,
        label: l10n.t('addPayment'),
        color: AppColors.success,
        route: AppRoutes.addPayment,
      ),
      _DialConfig(
        angleDeg: 64,
        icon: Icons.mic_outlined,
        label: l10n.t('voiceExpense'),
        color: const Color(0xFF7C3AED),
        route: AppRoutes.voiceExpense,
      ),
    ];

    // Nav-bar mapping: branch 0 ↔ nav 0 (Home), branch 2 ↔ nav 1 (Projects)
    final selectedNavIndex = widget.navigationShell.currentIndex == 2 ? 1 : 0;

    return PopScope(
      canPop: !_speedDialOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _speedDialOpen) _closeDial();
      },
      child: Stack(
        children: [
          // ── Scaffold (base layer) ──────────────────────────────────────
          Scaffold(
            body: Column(
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
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedNavIndex,
              onDestinationSelected: (int navIdx) {
                if (_speedDialOpen) _closeDial();
                final branchIndex = navIdx == 1 ? 2 : 0;
                widget.navigationShell.goBranch(
                  branchIndex,
                  initialLocation:
                      branchIndex == widget.navigationShell.currentIndex,
                );
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(
                    Icons.home_outlined,
                    key: Key('qa_nav_home'),
                  ),
                  selectedIcon: const Icon(
                    Icons.home,
                    key: Key('qa_nav_home'),
                  ),
                  label: l10n.t('home'),
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

          // ── Floating + button (half above nav bar, half inside) ────────
          Positioned(
            bottom: mq.padding.bottom + navVisualHeight - buttonRadius,
            left: mq.size.width / 2 - buttonRadius,
            child: GestureDetector(
              key: const Key('qa_nav_add'),
              onTap: _speedDialOpen ? _closeDial : _openDial,
              child: AnimatedContainer(
                width: buttonRadius * 2,
                height: buttonRadius * 2,
                duration: const Duration(milliseconds: 220),
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
                          .withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 5),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
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
              ),
            ),
          ),

          // ── Backdrop — covers entire screen including nav bar ──────────
          if (_speedDialOpen)
            FadeTransition(
              opacity: _animController,
              child: GestureDetector(
                onTap: _closeDial,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.black.withValues(alpha: 0.65)),
              ),
            ),

          // ── Arc speed-dial items ──────────────────────────────────────
          if (_speedDialOpen)
            ...dialItems.map((cfg) {
              final rad = cfg.angleDeg * math.pi / 180;
              final dx = arcRadius * math.sin(rad);
              final dy = arcRadius * math.cos(rad);

              final itemBottom = plusCenterFromScreenBottom + dy - itemHalfH;
              final itemLeft = mq.size.width / 2 + dx - itemHalfW;

              return Positioned(
                left: itemLeft,
                bottom: itemBottom,
                child: _AnimatedDialItem(
                  animation: _anim,
                  dx: dx,
                  dy: dy,
                  icon: cfg.icon,
                  label: cfg.label,
                  color: cfg.color,
                  onTap: () => _navigateFrom(cfg.route),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _AnimatedDialItem extends StatelessWidget {
  const _AnimatedDialItem({
    required this.animation,
    required this.dx,
    required this.dy,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Animation<double> animation;
  final double dx;
  final double dy;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        // t=0 → item at arc origin (+ button); t=1 → item at arc position.
        // Translate back: left by dx, down by dy (positive y = down in Flutter).
        return Transform.translate(
          offset: Offset(-dx * (1 - t), dy * (1 - t)),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 84,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(height: 7),
              Container(
                constraints: const BoxConstraints(maxWidth: 84),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C2E).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    height: 1.3,
                    decoration: TextDecoration.none,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
