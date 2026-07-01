import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/pending_attachment_service.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/services/sync_error_classifier.dart';
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
          .read(appTelemetryProvider)
          .trace(
            'offline_sync.drain',
            () => _ref
                .read(offlineActionQueueProvider)
                .drain(
                  _ref
                      .read(workspaceMutationServiceProvider)
                      .processQueuedAction,
                ),
          );
      await retryPendingAttachments();
    } finally {
      _draining = false;
      await refreshCounts();
    }
  }

  Future<void> retryPendingAttachments() async {
    final user = _ref.read(firebaseAuthProvider).currentUser;
    if (user == null) {
      return;
    }

    final pendingService = await _ref.read(
      pendingAttachmentServiceProvider.future,
    );
    final uploadService = _ref.read(storageUploadServiceProvider);
    final pending = await pendingService.listPending();
    for (final record in pending) {
      await pendingService.markUploading(id: record.id);
      try {
        final uploaded = await uploadService.uploadAttachment(
          userId: user.uid,
          localFilePath: record.attachment.localPath ?? '',
          fileName: record.attachment.fileName,
        );
        await pendingService.markUploadedAndRemove(
          id: record.id,
          storagePath: uploaded.storagePath,
          downloadUrl: uploaded.downloadUrl,
        );
      } on StorageUploadException catch (error) {
        if (error.code == 'missing-local-file') {
          await pendingService.markMissingLocalFile(id: record.id);
        } else {
          await pendingService.markFailed(
            id: record.id,
            message: error.message,
          );
          await _ref
              .read(appTelemetryProvider)
              .recordError(
                error,
                StackTrace.current,
                reason: 'attachment_upload.storage_error code=${error.code}',
              );
        }
      } catch (error, stackTrace) {
        await pendingService.markFailed(id: record.id, message: '$error');
        await _ref
            .read(appTelemetryProvider)
            .recordError(
              error,
              stackTrace,
              reason: 'attachment_upload.unexpected_error',
            );
      }
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

    _ref
        .read(appTelemetryProvider)
        .recordError(
          Exception(
            'offline_sync.dead_letter '
            'type=${latest.type} '
            'code=${latest.lastErrorCode} '
            'retries=${latest.retryCount} '
            'error=${latest.lastError}',
          ),
          StackTrace.empty,
          reason: 'offline_sync.dead_letter type=${latest.type}',
        );

    final type = _failureTypeFor(
      code: latest.lastErrorCode,
      message: latest.lastError,
    );
    _ref.read(offlineSyncNoticeProvider.notifier).state = OfflineSyncNotice(
      actionId: latest.id,
      type: type,
    );
    _ref.read(offlineLastNotifiedDeadLetterIdProvider.notifier).state =
        latest.id;
  }

  OfflineSyncFailureType _failureTypeFor({String? code, String? message}) {
    switch (SyncErrorClassifier.categoryFrom(code: code, message: message)) {
      case SyncFailureCategory.quota:
        return OfflineSyncFailureType.quota;
      case SyncFailureCategory.unauthenticated:
        return OfflineSyncFailureType.unauthenticated;
      case SyncFailureCategory.invalidTarget:
        return OfflineSyncFailureType.invalidTarget;
      case SyncFailureCategory.permission:
        return OfflineSyncFailureType.permission;
      case SyncFailureCategory.generic:
        return OfflineSyncFailureType.generic;
    }
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
  ProviderSubscription<AppUiNotice?>? _appNoticeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(workspaceSelectionSyncProvider);
    Future.microtask(() async {
      await ref.read(offlineQueueCoordinatorProvider).refreshCounts();
      await ref.read(offlineQueueCoordinatorProvider).drainNow();
    });
    _connectivitySubscription = ref.listenManual<AsyncValue<bool>>(
      connectivityProvider,
      (previous, next) {
        final wasOnline = previous?.value ?? false;
        final isOnline = next.value ?? false;
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
        final message = _messageForNotice(next.type);
        _showNotice(message);
      },
    );
    _appNoticeSubscription = ref.listenManual<AppUiNotice?>(
      appUiNoticeProvider,
      (previous, next) {
        if (next == null || previous?.id == next.id || !mounted) {
          return;
        }
        _showNotice(next.message);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.close();
    _syncNoticeSubscription?.close();
    _appNoticeSubscription?.close();
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

  void _showNotice(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageForNotice(OfflineSyncFailureType type) {
    final localizations = AppLocalizations.of(context);
    return switch (type) {
      OfflineSyncFailureType.quota => localizations.t(
        'offlineSyncFailureQuota',
      ),
      OfflineSyncFailureType.unauthenticated => localizations.t(
        'offlineSyncFailureUnauthenticated',
      ),
      OfflineSyncFailureType.invalidTarget => localizations.t(
        'offlineSyncFailureInvalidTarget',
      ),
      OfflineSyncFailureType.permission => localizations.t(
        'offlineSyncFailurePermission',
      ),
      OfflineSyncFailureType.generic => localizations.t(
        'offlineSyncFailureGeneric',
      ),
    };
  }
}
