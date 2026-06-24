import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final userId = ref.read(activeUserIdProvider);
      final workspaceId = ref.read(activeWorkspaceIdProvider);
      if (userId != null &&
          userId.isNotEmpty &&
          workspaceId != null &&
          workspaceId.isNotEmpty) {
        context.go(AppRoutes.dashboard);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _authErrorMessage(AppLocalizations l10n, String? code) {
    switch (code) {
      case 'user-not-found':
        return l10n.t('authNoAccountFound');
      case 'wrong-password':
      case 'invalid-credential':
        return l10n.t('authIncorrectPassword');
      case 'invalid-email':
        return l10n.t('authInvalidEmail');
      case 'user-disabled':
        return l10n.t('authAccountDisabled');
      case 'too-many-requests':
        return l10n.t('authTooManyAttempts');
      case 'network-request-failed':
        return l10n.t('authNetworkError');
      case 'account-exists-with-different-credential':
        return l10n.t('authDifferentProvider');
      default:
        return l10n.t('authSignInFailed');
    }
  }

  Future<void> _clearFailedSignInSession(
    FirebaseAuth auth, {
    bool includeGoogle = false,
  }) async {
    ref.read(activeUserIdProvider.notifier).state = null;
    ref.read(activeWorkspaceIdProvider.notifier).state = null;
    try {
      if (includeGoogle) {
        await ref.read(googleAuthServiceProvider).signOut();
      }
      await auth.signOut();
    } catch (_) {
      // Keep the visible login failure instead of replacing it with sign-out noise.
    }
  }

  Future<void> _loginWithGoogle() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = ref.read(firebaseAuthProvider);
    try {
      final credential = await ref
          .read(googleAuthServiceProvider)
          .signInWithGoogle(auth: auth);

      final user = credential?.user;
      if (user == null) {
        if (mounted) {
          setState(() {
            _error = l10n.t('signInCancelled');
            _loading = false;
          });
        }
        return;
      }

      final workspaceId = await ref
          .read(workspaceMutationServiceProvider)
          .ensureUserWorkspaceBootstrap();
      if (workspaceId.workspaceId.isEmpty) {
        throw StateError('Workspace bootstrap failed.');
      }
      ref.read(activeUserIdProvider.notifier).state = user.uid;
      ref.read(activeWorkspaceIdProvider.notifier).state =
          workspaceId.workspaceId;

      if (mounted) {
        context.go(
          workspaceId.setupCompleted
              ? AppRoutes.dashboard
              : AppRoutes.initialWorkspaceSetup,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        await _clearFailedSignInSession(auth, includeGoogle: true);
        setState(() => _error = _authErrorMessage(l10n, e.code));
      }
    } catch (_) {
      if (mounted) {
        await _clearFailedSignInSession(auth, includeGoogle: true);
        setState(() => _error = _authErrorMessage(l10n, null));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.surfaceGrey, // Subtle background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0, // Hide appbar to get full screen real estate visually
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/branding/app_icon.png',
                  key: const Key('login_app_icon'),
                  height: 72,
                  width: 72,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.t('welcomeBack'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.t('signInToContinue'),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: AppColors.textBody),
                ),
                const SizedBox(height: 48),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  key: const Key('google_sign_in_slot'),
                  height: 48,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final supported = ref.watch(
                        googleSignInSupportedProvider,
                      );
                      return supported.whenStale(
                        data: (isSupported) => isSupported
                            ? OutlinedButton.icon(
                                onPressed: _loading ? null : _loginWithGoogle,
                                icon: Image.asset(
                                  'assets/branding/google_g.png',
                                  height: 20,
                                  width: 20,
                                ),
                                label: Text(l10n.t('continueWithGoogle')),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: AppColors.surfaceSolid,
                                ),
                              )
                            : const SizedBox.shrink(),
                        loading: () =>
                            const LinearProgressIndicator(minHeight: 2),
                        error: (_, _) => const SizedBox.shrink(),
                      );
                    },
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
