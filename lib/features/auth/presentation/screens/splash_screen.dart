import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/app_remote_config.dart';
import 'package:buildtrack_app/core/services/session_restore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _updateRequired = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final config = await ref.read(appRemoteConfigProvider.future);
      if (!mounted) return;
      // Only ask the platform for the build number when a minimum is set:
      // the common path (no gate) then does no platform I/O before restore.
      if (config.minSupportedBuild > 0) {
        final info = await PackageInfo.fromPlatform();
        final build = int.tryParse(info.buildNumber) ?? 0;
        if (build < config.minSupportedBuild) {
          if (!mounted) return;
          setState(() => _updateRequired = true);
          return;
        }
      }
    } catch (_) {
      // Fail open if Remote Config or package info is unavailable.
    }

    SessionRestoreResult? restored;
    try {
      restored = await ref.read(sessionRestoreServiceProvider).restore();
    } catch (_) {
      // Keep startup recoverable if Firebase channels are not ready.
    }
    if (!mounted) return;

    if (restored == null) {
      context.go(AppRoutes.features);
      return;
    }

    ref.read(activeUserIdProvider.notifier).state = restored.userId;
    ref.read(activeWorkspaceIdProvider.notifier).state = restored.workspaceId;

    if (!restored.setupCompleted) {
      context.go(AppRoutes.initialWorkspaceSetup);
      return;
    }

    unawaited(ref.read(appPrefetcherProvider).warmCritical());
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    if (_updateRequired) {
      return Scaffold(
        backgroundColor: t.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsetsDirectional.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.t('updateRequiredTitle'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(l10n.t('updateRequiredBody'), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: t.accent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction, color: t.onAccent, size: 72),
            const SizedBox(height: 16),
            Text(
              l10n.t('appName'),
              style: TextStyle(
                color: t.onAccent,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('tagline'),
              style: TextStyle(color: t.onAccent, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
