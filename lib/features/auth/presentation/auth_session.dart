import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Finishes a successful authentication, whatever the provider was.
///
/// Google sign-in, email sign-in and email sign-up all converge here so the
/// workspace bootstrap, session providers and post-auth routing can never drift
/// apart between them.
///
/// Throws [StateError] if the workspace bootstrap returns no workspace.
Future<void> completeAuthSession({
  required WidgetRef ref,
  required BuildContext context,
  required User user,
}) async {
  final bootstrap = await ref
      .read(workspaceMutationServiceProvider)
      .ensureUserWorkspaceBootstrap();

  if (bootstrap.workspaceId.isEmpty) {
    throw StateError('Workspace bootstrap failed.');
  }

  ref.read(activeUserIdProvider.notifier).state = user.uid;
  ref.read(activeWorkspaceIdProvider.notifier).state = bootstrap.workspaceId;

  if (!context.mounted) {
    return;
  }
  context.go(
    bootstrap.setupCompleted
        ? AppRoutes.dashboard
        : AppRoutes.initialWorkspaceSetup,
  );
}

/// Clears session state after a failed sign-in so a half-authenticated user is
/// never left behind (e.g. Firebase user created but workspace bootstrap threw).
Future<void> clearFailedAuthSession({
  required WidgetRef ref,
  required FirebaseAuth auth,
  Future<void> Function()? alsoSignOut,
}) async {
  ref.read(activeUserIdProvider.notifier).state = null;
  ref.read(activeWorkspaceIdProvider.notifier).state = null;
  try {
    if (alsoSignOut != null) {
      await alsoSignOut();
    }
    await auth.signOut();
  } catch (_) {
    // Keep the visible failure instead of replacing it with sign-out noise.
  }
}
