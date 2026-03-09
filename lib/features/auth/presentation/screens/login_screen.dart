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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(firebaseAuthProvider);
      final firestore = ref.read(firestoreProvider);

      final cred = await auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = cred.user;
      if (user == null) {
        throw Exception('User not found');
      }

      final workspaceId = await _resolveWorkspaceId(firestore, user);
      ref.read(activeUserIdProvider.notifier).state = user.uid;
      ref.read(activeWorkspaceIdProvider.notifier).state = workspaceId;

      if (mounted) {
        context.go(AppRoutes.dashboard);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loginWithGoogle() async {
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
        return;
      }

      final workspaceId = await _resolveWorkspaceId(firestore, user);
      ref.read(activeUserIdProvider.notifier).state = user.uid;
      ref.read(activeWorkspaceIdProvider.notifier).state = workspaceId;

      if (mounted) {
        context.go(AppRoutes.dashboard);
      }
    } catch (e) {
      setState(() => _error = e.toString());
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
      await firestore.collection('memberships').add({
        'workspaceId': userWorkspaceId,
        'userId': user.uid,
        'role': 'owner',
        'createdAt': FieldValue.serverTimestamp(),
      });
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

    final batch = firestore.batch();
    batch.set(firestore.collection('users').doc(user.uid), {
      'id': user.uid,
      'fullName': displayName ?? '',
      'email': user.email ?? '',
      'phoneNumber': user.phoneNumber ?? '',
      'workspaceId': workspaceId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(firestore.collection('workspaces').doc(workspaceId), {
      'id': workspaceId,
      'name': workspaceName,
      'ownerId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(firestore.collection('memberships').doc(), {
      'workspaceId': workspaceId,
      'userId': user.uid,
      'role': 'owner',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return workspaceId;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('login'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l10n.t('email')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.t('password')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.t('login')),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loginWithGoogle,
              icon: const Icon(Icons.g_mobiledata, size: 24),
              label: const Text('Continue with Google'),
            ),
            TextButton(
              onPressed: () => context.go(AppRoutes.forgotPassword),
              child: Text(l10n.t('forgotPassword')),
            ),
            TextButton(
              onPressed: () => context.go(AppRoutes.signup),
              child: Text(l10n.t('signup')),
            ),
          ],
        ),
      ),
    );
  }
}
