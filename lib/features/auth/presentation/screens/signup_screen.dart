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

/// Minimum password length we enforce client-side. Firebase itself only
/// requires 6; we ask for 8 and say so before the request is sent.
const int kMinPasswordLength = 8;

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Returns a localized validation error, or null when the form is valid.
  String? _validate(AppLocalizations l10n) {
    if (_nameController.text.trim().isEmpty) {
      return l10n.t('authNameRequired');
    }
    final email = _emailController.text.trim();
    if (!isValidEmail(email)) {
      return l10n.t('authInvalidEmailFormat');
    }
    if (_passwordController.text.length < kMinPasswordLength) {
      return l10n.t('authPasswordMinLength');
    }
    if (_passwordController.text != _confirmController.text) {
      return l10n.t('authPasswordsDoNotMatch');
    }
    return null;
  }

  Future<void> _signUp() async {
    final l10n = AppLocalizations.of(context);
    final validationError = _validate(l10n);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = ref.read(firebaseAuthProvider);
    try {
      final credential = await ref
          .read(emailAuthServiceProvider)
          .signUp(
            auth: auth,
            email: _emailController.text,
            password: _passwordController.text,
            displayName: _nameController.text,
          );

      final user = credential.user;
      if (user == null) {
        throw StateError('Sign-up returned no user.');
      }
      if (!mounted) return;
      await completeAuthSession(ref: ref, context: context, user: user);
    } catch (e) {
      if (!mounted) return;
      await clearFailedAuthSession(ref: ref, auth: auth);
      if (!mounted) return;
      setState(() => _error = AuthErrorMessages.signUp(l10n, e));
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
          key: const Key('qa_signup_back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.t('signup'),
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.t('signUpToContinue'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: t.textMuted),
                ),
                const SizedBox(height: 28),
                if (_error != null) ...[
                  AuthErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ],
                BuildTextField(
                  key: const Key('qa_signup_name'),
                  label: l10n.t('fullName'),
                  controller: _nameController,
                  enabled: !_loading,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                ),
                const SizedBox(height: 16),
                BuildTextField(
                  key: const Key('qa_signup_email'),
                  label: l10n.t('email'),
                  controller: _emailController,
                  enabled: !_loading,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 16),
                BuildTextField(
                  key: const Key('qa_signup_password'),
                  label: l10n.t('password'),
                  controller: _passwordController,
                  enabled: !_loading,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 16),
                BuildTextField(
                  key: const Key('qa_signup_confirm'),
                  label: l10n.t('confirmPassword'),
                  controller: _confirmController,
                  enabled: !_loading,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _loading ? null : _signUp(),
                ),
                const SizedBox(height: 28),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else
                  BuildButton(
                    key: const Key('qa_signup_submit'),
                    label: l10n.t('signup'),
                    size: BuildButtonSize.lg,
                    full: true,
                    onPressed: _signUp,
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.t('alreadyHaveAccount'),
                      style: TextStyle(fontSize: 14, color: t.textMuted),
                    ),
                    TextButton(
                      key: const Key('qa_signup_to_login'),
                      onPressed: _loading
                          ? null
                          : () => context.canPop()
                                ? context.pop()
                                : context.go(AppRoutes.login),
                      child: Text(l10n.t('login')),
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

/// Shared, deliberately permissive email check: reject the obviously-malformed
/// before spending a network round-trip, and let Firebase be the real authority.
bool isValidEmail(String email) {
  final value = email.trim();
  if (value.isEmpty || value.contains(' ')) return false;
  final at = value.indexOf('@');
  if (at <= 0 || at != value.lastIndexOf('@')) return false;
  final domain = value.substring(at + 1);
  return domain.contains('.') &&
      !domain.startsWith('.') &&
      !domain.endsWith('.');
}
