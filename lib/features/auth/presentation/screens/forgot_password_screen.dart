import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  String? _info;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _info = null;
      _error = null;
    });
    try {
      await ref
          .read(firebaseAuthProvider)
          .sendPasswordResetEmail(email: _emailController.text.trim());
      if (mounted) {
        setState(() => _info = l10n.t('resetLinkSent'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = appErrorMessage(l10n, e));
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
    return AppBackScope(
      fallbackRoute: AppRoutes.login,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('forgotPassword'),
          fallbackRoute: AppRoutes.login,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _emailController,
                decoration: InputDecoration(labelText: l10n.t('email')),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading ? null : _sendReset,
                child: _loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.t('sendResetLink')),
              ),
              if (_info != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _info!,
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
