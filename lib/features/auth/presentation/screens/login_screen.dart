import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/app/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  String? _error;
  String? _emailError;
  String? _passwordError;

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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final emailError = email.isEmpty ? l10n.t('loginEmailRequired') : null;
    final passwordError = password.isEmpty
        ? l10n.t('loginPasswordRequired')
        : null;
    if (emailError != null || passwordError != null) {
      setState(() {
        _emailError = emailError;
        _passwordError = passwordError;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _emailError = null;
      _passwordError = null;
    });
    final auth = ref.read(firebaseAuthProvider);
    try {
      final cred = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw Exception('User not found');
      }

      final workspaceId =
          (await ref
                  .read(workspaceMutationServiceProvider)
                  .ensureUserWorkspaceBootstrap())
              .trim();
      if (workspaceId.isEmpty) {
        throw const CallableClientException('Workspace bootstrap failed.');
      }
      ref.read(activeUserIdProvider.notifier).state = user.uid;
      ref.read(activeWorkspaceIdProvider.notifier).state = workspaceId;

      if (mounted) {
        context.go(AppRoutes.dashboard);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        await _clearFailedSignInSession(auth);
        setState(() => _error = _authErrorMessage(l10n, e.code));
      }
    } catch (_) {
      if (mounted) {
        await _clearFailedSignInSession(auth);
        setState(() => _error = _authErrorMessage(l10n, null));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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

      final workspaceId =
          (await ref
                  .read(workspaceMutationServiceProvider)
                  .ensureUserWorkspaceBootstrap())
              .trim();
      if (workspaceId.isEmpty) {
        throw const CallableClientException('Workspace bootstrap failed.');
      }
      ref.read(activeUserIdProvider.notifier).state = user.uid;
      ref.read(activeWorkspaceIdProvider.notifier).state = workspaceId;

      if (mounted) {
        context.go(AppRoutes.dashboard);
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
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSolid,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.softShadow,
                    border: Border.all(
                      color: AppColors.borderGrey.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: l10n.t('email'),
                          prefixIcon: const Icon(Icons.email_outlined),
                          errorText: _emailError,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: l10n.t('password'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          errorText: _passwordError,
                          suffixIcon: IconButton(
                            key: const Key('password_visibility_toggle'),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
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
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.go(AppRoutes.forgotPassword),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textBody,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(l10n.t('forgotPassword')),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.surfaceSolid,
                                ),
                              )
                            : Text(
                                l10n.t('login'),
                                style: const TextStyle(fontSize: 16),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  key: const Key('google_sign_in_slot'),
                  height: 48,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final supported = ref.watch(
                        googleSignInSupportedProvider,
                      );
                      return supported.when(
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
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.t('dontHaveAccount'),
                      style: const TextStyle(color: AppColors.textBody),
                    ),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.signup),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.constructionOrange,
                      ),
                      child: Text(
                        l10n.t('signup'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
