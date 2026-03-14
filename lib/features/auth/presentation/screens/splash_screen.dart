import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'dart:async';

import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/session_restore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }

    final restored = await ref.read(sessionRestoreServiceProvider).restore();
    if (!mounted) {
      return;
    }

    if (restored == null) {
      context.go(AppRoutes.features);
      return;
    }

    ref.read(activeUserIdProvider.notifier).state = restored.userId;
    ref.read(activeWorkspaceIdProvider.notifier).state = restored.workspaceId;
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF7A00), Color(0xFFFF8C1A), Color(0xFFFF9E33)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction, color: Colors.white, size: 72),
              const SizedBox(height: 16),
              Text(
                l10n.t('appName'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.t('tagline'),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
