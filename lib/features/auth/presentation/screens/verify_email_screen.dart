import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/utils/auth_error_messages.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/auth/presentation/auth_session.dart';
import 'package:buildtrack_app/features/auth/presentation/widgets/auth_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// How long the user must wait between verification emails. Firebase rate-limits
/// server-side too; this stops us from burning that budget on double-taps.
const Duration kResendCooldown = Duration(seconds: 60);

/// Holds an unverified email/password user until they click the link we mailed.
///
/// Reached only via the router gate (see `resolveAppRedirect`), so it cannot be
/// bypassed by deep-linking into the app. The workspace is deliberately NOT
/// bootstrapped until verification succeeds.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _checking = false;
  bool _resending = false;
  String? _error;
  String? _info;

  Timer? _cooldownTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    // Send the first email as soon as the user lands here after sign-up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _sendEmail();
      }
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = kResendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
      }
    });
  }

  Future<void> _sendEmail() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });

    try {
      await ref
          .read(emailAuthServiceProvider)
          .sendVerificationEmail(auth: ref.read(firebaseAuthProvider));
      if (!mounted) return;
      setState(() => _info = l10n.t('verificationEmailSent'));
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthErrorMessages.signIn(l10n, e));
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  Future<void> _checkVerified() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _checking = true;
      _error = null;
      _info = null;
    });

    final auth = ref.read(firebaseAuthProvider);
    try {
      final verified = await ref
          .read(emailAuthServiceProvider)
          .refreshEmailVerified(auth: auth);

      if (!verified) {
        if (mounted) {
          setState(() => _error = l10n.t('emailNotVerifiedYet'));
        }
        return;
      }

      final user = auth.currentUser;
      if (user == null) {
        throw StateError('Verified but no current user.');
      }
      if (!mounted) return;
      // Verification passed — only now do we create the workspace.
      await completeAuthSession(ref: ref, context: context, user: user);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthErrorMessages.signIn(l10n, e));
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _signOut() async {
    final auth = ref.read(firebaseAuthProvider);
    await clearFailedAuthSession(ref: ref, auth: auth);
    if (mounted) {
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final email = ref.read(firebaseAuthProvider).currentUser?.email ?? '';
    final canResend = _secondsLeft <= 0 && !_resending;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mark_email_unread_outlined, size: 64, color: t.accent),
                const SizedBox(height: 24),
                Text(
                  l10n.t('verifyEmailTitle'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.t('verifyEmailSubtitle', params: {'email': email}),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: t.textMuted),
                ),
                const SizedBox(height: 28),
                if (_error != null) ...[
                  AuthErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ],
                if (_info != null) ...[
                  AuthInfoBanner(message: _info!),
                  const SizedBox(height: 16),
                ],
                if (_checking)
                  const Center(child: CircularProgressIndicator())
                else
                  BuildButton(
                    key: const Key('qa_verify_continue'),
                    label: l10n.t('iVerifiedContinue'),
                    size: BuildButtonSize.lg,
                    full: true,
                    onPressed: _checkVerified,
                  ),
                const SizedBox(height: 12),
                BuildButton(
                  key: const Key('qa_verify_resend'),
                  label: _secondsLeft > 0
                      ? l10n.t(
                          'resendInSeconds',
                          params: {'seconds': '$_secondsLeft'},
                        )
                      : l10n.t('resendVerificationEmail'),
                  variant: BuildButtonVariant.outline,
                  size: BuildButtonSize.lg,
                  full: true,
                  onPressed: canResend ? _sendEmail : null,
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('qa_verify_signout'),
                  onPressed: _checking ? null : _signOut,
                  child: Text(l10n.t('logout')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
