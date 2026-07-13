import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/utils/auth_error_messages.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/signup_screen.dart'
    show isValidEmail;
import 'package:buildtrack_app/features/auth/presentation/widgets/auth_error_banner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final l10n = AppLocalizations.of(context);
    if (!isValidEmail(_emailController.text)) {
      setState(() {
        _error = l10n.t('authInvalidEmailFormat');
        _info = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      await ref
          .read(emailAuthServiceProvider)
          .sendPasswordReset(
            auth: ref.read(firebaseAuthProvider),
            email: _emailController.text,
          );
      if (mounted) {
        setState(() => _info = l10n.t('resetLinkSent'));
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // Never confirm whether an address is registered — that would let anyone
      // enumerate accounts. Unknown email looks exactly like a sent link.
      if (e.code.replaceFirst('firebase_auth/', '') == 'user-not-found') {
        setState(() => _info = l10n.t('resetLinkSent'));
        return;
      }
      setState(() => _error = AuthErrorMessages.passwordReset(l10n, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthErrorMessages.passwordReset(l10n, e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          key: const Key('qa_forgot_back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.t('forgotPassword'),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.t('resetPasswordSubtitle'),
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
              BuildTextField(
                key: const Key('qa_forgot_email'),
                label: l10n.t('email'),
                controller: _emailController,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                onSubmitted: (_) => _loading ? null : _sendReset(),
              ),
              const SizedBox(height: 28),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                BuildButton(
                  key: const Key('qa_forgot_submit'),
                  label: l10n.t('sendResetLink'),
                  size: BuildButtonSize.lg,
                  full: true,
                  onPressed: _sendReset,
                ),
              const SizedBox(height: 16),
              TextButton(
                key: const Key('qa_forgot_to_login'),
                onPressed: _loading
                    ? null
                    : () => context.canPop()
                          ? context.pop()
                          : context.go(AppRoutes.login),
                child: Text(l10n.t('backToSignIn')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
