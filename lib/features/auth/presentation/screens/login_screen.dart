import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/email_auth_service.dart';
import 'package:buildtrack_app/core/services/google_auth_service.dart';
import 'package:buildtrack_app/core/utils/auth_error_messages.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/auth/presentation/auth_session.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/signup_screen.dart'
    show isValidEmail;
import 'package:buildtrack_app/features/auth/presentation/widgets/auth_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithEmail() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = l10n.t('pleaseEnterEmailAndPassword'));
      return;
    }
    if (!isValidEmail(email)) {
      setState(() => _error = l10n.t('authInvalidEmailFormat'));
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
          .signIn(auth: auth, email: email, password: password);

      final user = credential.user;
      if (user == null) {
        throw StateError('Sign-in returned no user.');
      }
      if (!mounted) return;
      if (requiresEmailVerification(user)) {
        // Signed in, but hold them at verification rather than bootstrapping.
        context.go(AppRoutes.verifyEmail);
        return;
      }
      await completeAuthSession(ref: ref, context: context, user: user);
    } catch (e) {
      if (!mounted) return;
      await clearFailedAuthSession(ref: ref, auth: auth);
      if (!mounted) return;
      setState(() => _error = AuthErrorMessages.signIn(l10n, e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = ref.read(firebaseAuthProvider);
    Future<void> signOutGoogle() =>
        ref.read(googleAuthServiceProvider).signOut();

    try {
      final credential = await ref
          .read(googleAuthServiceProvider)
          .signInWithGoogle(auth: auth);

      final user = credential?.user;
      if (user == null) {
        // Null (rather than a thrown error) means the user backed out.
        if (mounted) {
          setState(() {
            _error = l10n.t('signInCancelled');
            _loading = false;
          });
        }
        return;
      }
      if (!mounted) return;
      await completeAuthSession(ref: ref, context: context, user: user);
    } on GoogleSignInConfigException {
      if (!mounted) return;
      await clearFailedAuthSession(
        ref: ref,
        auth: auth,
        alsoSignOut: signOutGoogle,
      );
      if (!mounted) return;
      setState(() => _error = l10n.t('authGoogleConfigError'));
    } catch (e) {
      if (!mounted) return;
      await clearFailedAuthSession(
        ref: ref,
        auth: auth,
        alsoSignOut: signOutGoogle,
      );
      if (!mounted) return;
      setState(() => _error = AuthErrorMessages.signIn(l10n, e));
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
        toolbarHeight: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: AutofillGroup(
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
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('welcomeSub'),
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: t.textMuted),
                  ),
                  const SizedBox(height: 32),
                  if (_error != null) ...[
                    AuthErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],
                  BuildTextField(
                    key: const Key('qa_login_email'),
                    label: l10n.t('email'),
                    controller: _emailController,
                    enabled: !_loading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 16),
                  BuildTextField(
                    key: const Key('qa_login_password'),
                    label: l10n.t('password'),
                    controller: _passwordController,
                    enabled: !_loading,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _loading ? null : _loginWithEmail(),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      key: const Key('qa_login_forgot'),
                      onPressed: _loading
                          ? null
                          : () => context.push(AppRoutes.forgotPassword),
                      child: Text(l10n.t('forgotPassword')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else
                    BuildButton(
                      key: const Key('qa_login_submit'),
                      label: l10n.t('login'),
                      size: BuildButtonSize.lg,
                      full: true,
                      onPressed: _loginWithEmail,
                    ),
                  const SizedBox(height: 20),
                  _OrDivider(label: l10n.t('orContinueWith')),
                  const SizedBox(height: 20),
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
                                  label: Text(
                                    l10n.t('continueWithGoogle'),
                                    style: TextStyle(
                                      color: t.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15.5,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: t.surface,
                                    side: BorderSide(
                                      color: t.borderStrong,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        t.rMd,
                                      ),
                                    ),
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
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l10n.t('dontHaveAccount'),
                        style: TextStyle(fontSize: 14, color: t.textMuted),
                      ),
                      TextButton(
                        key: const Key('qa_login_to_signup'),
                        onPressed: _loading
                            ? null
                            : () => context.push(AppRoutes.signup),
                        child: Text(l10n.t('signup')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(child: Divider(color: t.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: t.textFaint),
          ),
        ),
        Expanded(child: Divider(color: t.border)),
      ],
    );
  }
}
