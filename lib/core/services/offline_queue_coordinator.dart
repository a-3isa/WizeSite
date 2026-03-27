import 'dart:async';

import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OfflineQueueCoordinator {
  OfflineQueueCoordinator(this._ref);

  final Ref _ref;
  bool _draining = false;

  Future<void> refreshCounts() async {
    final queue = _ref.read(offlineActionQueueProvider);
    final pendingCount = await queue.pendingCount();
    final deadLetters = await queue.deadLetters();
    final deadLetterCount = deadLetters.length;
    _ref.read(offlinePendingCountProvider.notifier).state = pendingCount;
    _ref.read(offlineDeadLetterCountProvider.notifier).state = deadLetterCount;
    _publishDeadLetterNotice(deadLetters);
  }

  Future<void> drainNow() async {
    if (_draining) {
      return;
    }
    if (_ref.read(firebaseAuthProvider).currentUser == null) {
      await refreshCounts();
      return;
    }

    _draining = true;
    try {
      await _ref
          .read(offlineActionQueueProvider)
          .drain(
            _ref.read(workspaceMutationServiceProvider).processQueuedAction,
          );
    } finally {
      _draining = false;
      await refreshCounts();
    }
  }

  void _publishDeadLetterNotice(List<OfflineAction> deadLetters) {
    if (deadLetters.isEmpty) {
      return;
    }
    deadLetters.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latest = deadLetters.first;
    final alreadyNotified =
        _ref.read(offlineLastNotifiedDeadLetterIdProvider) == latest.id;
    if (alreadyNotified) {
      return;
    }

    final type = _failureTypeFor(latest.lastError);
    _ref.read(offlineSyncNoticeProvider.notifier).state = OfflineSyncNotice(
      actionId: latest.id,
      type: type,
    );
    _ref.read(offlineLastNotifiedDeadLetterIdProvider.notifier).state =
        latest.id;
  }

  OfflineSyncFailureType _failureTypeFor(String? rawError) {
    final text = rawError?.toLowerCase() ?? '';
    if (text.contains('limit_reached') ||
        text.contains('failed-precondition')) {
      return OfflineSyncFailureType.quota;
    }
    if (text.contains('unauthenticated')) {
      return OfflineSyncFailureType.unauthenticated;
    }
    return OfflineSyncFailureType.generic;
  }
}

final offlineQueueCoordinatorProvider = Provider<OfflineQueueCoordinator>((
  ref,
) {
  return OfflineQueueCoordinator(ref);
});

class AppBootstrapScope extends ConsumerStatefulWidget {
  const AppBootstrapScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppBootstrapScope> createState() => _AppBootstrapScopeState();
}

class _AppBootstrapScopeState extends ConsumerState<AppBootstrapScope>
    with WidgetsBindingObserver {
  ProviderSubscription<AsyncValue<bool>>? _connectivitySubscription;
  ProviderSubscription<OfflineSyncNotice?>? _syncNoticeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      await ref.read(offlineQueueCoordinatorProvider).refreshCounts();
      await ref.read(offlineQueueCoordinatorProvider).drainNow();
    });
    _connectivitySubscription = ref.listenManual<AsyncValue<bool>>(
      connectivityProvider,
      (previous, next) {
        final wasOnline = previous?.valueOrNull ?? false;
        final isOnline = next.valueOrNull ?? false;
        if (!wasOnline && isOnline) {
          unawaited(ref.read(offlineQueueCoordinatorProvider).drainNow());
        }
      },
    );
    _syncNoticeSubscription = ref.listenManual<OfflineSyncNotice?>(
      offlineSyncNoticeProvider,
      (previous, next) {
        if (next == null || previous?.actionId == next.actionId || !mounted) {
          return;
        }
        final message = switch (next.type) {
          OfflineSyncFailureType.quota =>
            'Queued action was rejected: plan limit reached.',
          OfflineSyncFailureType.unauthenticated =>
            'Queued sync requires sign-in. Please log in again.',
          OfflineSyncFailureType.generic => 'A queued action failed to sync.',
        };
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(content: Text(message)),
        // );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.close();
    _syncNoticeSubscription?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(offlineQueueCoordinatorProvider).drainNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
