import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

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
  String? _error;

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
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = l10n.t('pleaseEnterEmailAndPassword'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(firebaseAuthProvider);
      final firestore = ref.read(firestoreProvider);

      final cred = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw Exception('User not found');
      }

      await firestore.collection('users').doc(user.uid).set({
        'email': email,
        'fullName': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
        'defaultCurrency': 'EGP',
        'riskAlertsEnabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final workspaceId = await _resolveWorkspaceId(firestore, user);
      ref.read(activeUserIdProvider.notifier).state = user.uid;
      ref.read(activeWorkspaceIdProvider.notifier).state = workspaceId;

      if (mounted) {
        context.go(AppRoutes.dashboard);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _authErrorMessage(l10n, e.code));
      }
    } catch (_) {
      if (mounted) {
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

  Future<void> _loginWithGoogle() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = ref.read(firebaseAuthProvider);
      final firestore = ref.read(firestoreProvider);
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

      await firestore.collection('users').doc(user.uid).set({
        'email': (user.email ?? '').trim().toLowerCase(),
        'fullName': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
        'defaultCurrency': 'EGP',
        'riskAlertsEnabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final workspaceId = await _resolveWorkspaceId(firestore, user);
      ref.read(activeUserIdProvider.notifier).state = user.uid;
      ref.read(activeWorkspaceIdProvider.notifier).state = workspaceId;

      if (mounted) {
        context.go(AppRoutes.dashboard);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _authErrorMessage(l10n, e.code));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = _authErrorMessage(l10n, null));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String> _resolveWorkspaceId(
    FirebaseFirestore firestore,
    User user,
  ) async {
    final snap = await firestore
        .collection('memberships')
        .where('userId', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      final workspaceId = snap.docs.first.data()['workspaceId'] as String?;
      if (workspaceId != null && workspaceId.isNotEmpty) {
        return workspaceId;
      }
    }

    final userDoc = await firestore.collection('users').doc(user.uid).get();
    final userWorkspaceId = userDoc.data()?['workspaceId'] as String?;
    if (userWorkspaceId != null && userWorkspaceId.isNotEmpty) {
      await _ensureWorkspaceExists(
        firestore: firestore,
        workspaceId: userWorkspaceId,
        user: user,
      );
      await _ensureOwnerMembership(
        firestore: firestore,
        workspaceId: userWorkspaceId,
        user: user,
      );
      return userWorkspaceId;
    }

    return _createWorkspaceForUser(firestore: firestore, user: user);
  }

  Future<String> _createWorkspaceForUser({
    required FirebaseFirestore firestore,
    required User user,
  }) async {
    final workspaceId = const Uuid().v4();
    final displayName = user.displayName?.trim();
    final workspaceName = (displayName != null && displayName.isNotEmpty)
        ? '$displayName Workspace'
        : 'New Workspace';

    await firestore.collection('workspaces').doc(workspaceId).set({
      'id': workspaceId,
      'name': workspaceName,
      'ownerId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await firestore.collection('users').doc(user.uid).set({
      'id': user.uid,
      'fullName': displayName ?? '',
      'email': (user.email ?? '').trim().toLowerCase(),
      'phoneNumber': user.phoneNumber ?? '',
      'workspaceId': workspaceId,
      'photoUrl': user.photoURL ?? '',
      'defaultCurrency': 'EGP',
      'riskAlertsEnabled': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _membershipDocRef(
      firestore: firestore,
      workspaceId: workspaceId,
      userId: user.uid,
    ).set({
      'workspaceId': workspaceId,
      'userId': user.uid,
      'role': 'owner',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return workspaceId;
  }

  Future<void> _ensureOwnerMembership({
    required FirebaseFirestore firestore,
    required String workspaceId,
    required User user,
  }) async {
    final existing = await firestore
        .collection('memberships')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('userId', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      return;
    }

    final workspace = await firestore
        .collection('workspaces')
        .doc(workspaceId)
        .get();
    final ownerId = workspace.data()?['ownerId'] as String?;
    if (ownerId != user.uid) {
      return;
    }

    await _membershipDocRef(
      firestore: firestore,
      workspaceId: workspaceId,
      userId: user.uid,
    ).set({
      'workspaceId': workspaceId,
      'userId': user.uid,
      'role': 'owner',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _ensureWorkspaceExists({
    required FirebaseFirestore firestore,
    required String workspaceId,
    required User user,
  }) async {
    final workspaceRef = firestore.collection('workspaces').doc(workspaceId);
    final workspaceSnap = await workspaceRef.get();
    if (workspaceSnap.exists) {
      return;
    }
    await workspaceRef.set({
      'id': workspaceId,
      'name': '${user.displayName ?? 'Workspace'} Workspace',
      'ownerId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  DocumentReference<Map<String, dynamic>> _membershipDocRef({
    required FirebaseFirestore firestore,
    required String workspaceId,
    required String userId,
  }) {
    return firestore.collection('memberships').doc('${workspaceId}_$userId');
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
                Icon(
                  Icons.construction_rounded, // App Logo Placeholder
                  size: 64,
                  color: AppColors.constructionOrange,
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
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.t('password'),
                          prefixIcon: const Icon(Icons.lock_outline),
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
                Consumer(
                  builder: (context, ref, _) {
                    final supported = ref.watch(googleSignInSupportedProvider);
                    return supported.when(
                      data: (isSupported) => isSupported
                          ? OutlinedButton.icon(
                              onPressed: _loading ? null : _loginWithGoogle,
                              icon: Image.network(
                                'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg',
                                height: 20,
                                width: 20,
                                errorBuilder: (c, e, s) =>
                                    const Icon(Icons.g_mobiledata, size: 24),
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
