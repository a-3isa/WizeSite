import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/cache/workspace_cache.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
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
    final cache = ref.read(workspaceCacheProvider);
    final cachedWorkspaceId = cache.activeWorkspaceId;
    final cachedUserId = cache.activeUserId;

    // Fast path: a returning, still-signed-in user goes straight to the
    // dashboard from the local cache. The authoritative session restore runs
    // in the background and only corrects the context if the server disagrees,
    // so startup is never blocked on the network.
    if (cachedWorkspaceId != null && cachedUserId != null) {
      final currentUser = ref.read(firebaseAuthProvider).currentUser;
      if (currentUser != null) {
        ref.read(activeUserIdProvider.notifier).state = currentUser.uid;
        ref.read(activeWorkspaceIdProvider.notifier).state = cachedWorkspaceId;
        unawaited(ref.read(appPrefetcherProvider).warmCritical());
        if (mounted) context.go(AppRoutes.dashboard);
        unawaited(_restoreInBackground());
        return;
      }
    }

    // Cold path: no cached session — restore synchronously then route.
    SessionRestoreResult? restored;
    try {
      restored = await ref.read(sessionRestoreServiceProvider).restore();
    } catch (_) {
      // Firestore platform channel unavailable — fall through to login.
    }
    if (!mounted) return;

    if (restored == null) {
      if (mounted) context.go(AppRoutes.features);
      return;
    }

    ref.read(activeUserIdProvider.notifier).state = restored.userId;
    ref.read(activeWorkspaceIdProvider.notifier).state = restored.workspaceId;

    unawaited(ref.read(appPrefetcherProvider).warmCritical());
    if (mounted) context.go(AppRoutes.dashboard);
  }

  /// Validates the cached session against the backend without blocking the UI.
  /// Only updates the active context when the restored values differ from what
  /// was already seeded from cache.
  Future<void> _restoreInBackground() async {
    SessionRestoreResult? restored;
    try {
      restored = await ref.read(sessionRestoreServiceProvider).restore();
    } catch (_) {
      return;
    }
    if (!mounted || restored == null) {
      return;
    }
    if (ref.read(activeUserIdProvider) != restored.userId) {
      ref.read(activeUserIdProvider.notifier).state = restored.userId;
    }
    if (ref.read(activeWorkspaceIdProvider) != restored.workspaceId) {
      ref.read(activeWorkspaceIdProvider.notifier).state = restored.workspaceId;
    }
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
        child: Stack(
          children: [
            Center(
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
          ],
        ),
      ),
    );
  }
}
