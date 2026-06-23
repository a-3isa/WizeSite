import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

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
  final _companyController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  static const _signupTimeout = Duration(seconds: 30);

  String _authErrorMessage(Object e, AppLocalizations l10n) {
    if (e is FirebaseAuthException) {
      final code = e.code.replaceFirst('firebase_auth/', '');
      switch (code) {
        case 'email-already-in-use':
          return l10n.t('authEmailAlreadyInUse');
        case 'invalid-email':
          return l10n.t('authInvalidEmailFormat');
        case 'weak-password':
          return l10n.t('authWeakPassword');
        case 'operation-not-allowed':
          return l10n.t('authOperationNotAllowed');
        case 'network-request-failed':
        case 'too-many-requests':
          return l10n.t('authNetworkError');
      }
    }
    if (e is TimeoutException) {
      return l10n.t('authSignUpFailed');
    }
    return l10n.t('authSignUpFailed');
  }

  Future<void> _signup() async {
    final l10n = AppLocalizations.of(context);
    if (!_emailController.text.contains('@')) {
      setState(() => _error = l10n.t('authInvalidEmailFormat'));
      return;
    }
    if (_passwordController.text.length < 8) {
      setState(() => _error = l10n.t('authPasswordMinLength'));
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = l10n.t('authPasswordsDoNotMatch'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = ref.read(firebaseAuthProvider);
      final firestore = ref.read(firestoreProvider);
      final email = _emailController.text.trim().toLowerCase();
      final fullName = _nameController.text.trim();
      final companyName = _companyController.text.trim();
      final phoneNumber = _phoneController.text.trim();

      final cred = await auth
          .createUserWithEmailAndPassword(
            email: email,
            password: _passwordController.text,
          )
          .timeout(_signupTimeout);

      final uid = cred.user!.uid;
      final workspaceId = const Uuid().v4();
      await cred.user!.updateDisplayName(fullName);

      await firestore.collection('workspaces').doc(workspaceId).set({
        'id': workspaceId,
        'name': companyName.isEmpty ? '$fullName Workspace' : companyName,
        'ownerId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await firestore.collection('users').doc(uid).set({
        'id': uid,
        'fullName': fullName,
        'email': email,
        'phoneNumber': phoneNumber,
        'companyName': companyName,
        'workspaceId': workspaceId,
        'photoUrl': '',
        'defaultCurrency': 'EGP',
        'riskAlertsEnabled': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await firestore.collection('memberships').doc('${workspaceId}_$uid').set({
        'workspaceId': workspaceId,
        'userId': uid,
        'role': 'owner',
        'createdAt': FieldValue.serverTimestamp(),
      });

      ref.read(activeUserIdProvider.notifier).state = uid;
      ref.read(activeWorkspaceIdProvider.notifier).state = workspaceId;

      if (!cred.user!.emailVerified) {
        unawaited(cred.user!.sendEmailVerification());
      }

      if (mounted) {
        context.go(AppRoutes.dashboard);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _authErrorMessage(e, l10n));
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
          title: l10n.t('signup'),
          fallbackRoute: AppRoutes.login,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: l10n.t('fullName')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: l10n.t('email')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: l10n.t('password'),
                  suffixIcon: IconButton(
                    key: const Key('signup_password_visibility_toggle'),
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
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: !_showConfirmPassword,
                decoration: InputDecoration(
                  labelText: l10n.t('confirmPassword'),
                  suffixIcon: IconButton(
                    key: const Key('signup_confirm_visibility_toggle'),
                    onPressed: () => setState(
                      () => _showConfirmPassword = !_showConfirmPassword,
                    ),
                    icon: Icon(
                      _showConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _companyController,
                decoration: InputDecoration(
                  labelText: l10n.t('companyNameOptional'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: l10n.t('phoneNumberOptional'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _signup,
                child: _loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.t('signup')),
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.login),
                child: Text(l10n.t('login')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
