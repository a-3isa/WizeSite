import 'dart:async';
import 'dart:convert';

import 'package:buildtrack_app/core/services/sync_error_classifier.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

class OfflineAction {
  const OfflineAction({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
    this.lastErrorCode,
    this.status = OfflineActionStatus.pending,
    this.nextAttemptAt,
    this.syncedAt,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;
  final String? lastErrorCode;
  final String status;
  final DateTime? nextAttemptAt;
  final DateTime? syncedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
    'lastError': lastError,
    'lastErrorCode': lastErrorCode,
    'status': status,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'syncedAt': syncedAt?.toIso8601String(),
  };

  factory OfflineAction.fromMap(Map<String, dynamic> map) {
    return OfflineAction(
      id: map['id'] as String,
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      createdAt: DateTime.parse(map['createdAt'] as String),
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      lastError: map['lastError'] as String?,
      lastErrorCode: map['lastErrorCode'] as String?,
      status: map['status'] as String? ?? OfflineActionStatus.pending,
      nextAttemptAt: map['nextAttemptAt'] == null
          ? null
          : DateTime.tryParse(map['nextAttemptAt'] as String),
      syncedAt: map['syncedAt'] == null
          ? null
          : DateTime.tryParse(map['syncedAt'] as String),
    );
  }

  OfflineAction copyWith({
    int? retryCount,
    String? lastError,
    String? lastErrorCode,
    String? status,
    DateTime? nextAttemptAt,
    DateTime? syncedAt,
    bool clearLastError = false,
    bool clearNextAttemptAt = false,
    bool clearSyncedAt = false,
  }) {
    return OfflineAction(
      id: id,
      type: type,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastErrorCode: clearLastError
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
      status: status ?? this.status,
      nextAttemptAt: clearNextAttemptAt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
      syncedAt: clearSyncedAt ? null : (syncedAt ?? this.syncedAt),
    );
  }
}

abstract final class OfflineActionStatus {
  static const pending = 'pending';
  static const failed = 'failed';
  static const synced = 'synced';
  static const deadLetter = 'dead_letter';
}

abstract final class OfflineActionQueueTypes {
  static const attachmentUpload = 'attachment_upload';
  static const entityUpsert = 'entity_upsert';
  static const summaryDelta = 'summary_delta';
}

abstract final class OfflineActionPayloadKeys {
  static const workspaceId = 'workspaceId';
  static const ownerType = 'ownerType';
  static const ownerId = 'ownerId';
  static const attachment = 'attachment';
  static const entity = 'entity';
  static const summaryScope = 'summaryScope';
  static const summaryId = 'summaryId';
  static const summaryDelta = 'summaryDelta';
  static const clientMutationId = 'clientMutationId';
  static const clientCreatedAt = 'clientCreatedAt';
  static const clientUpdatedAt = 'clientUpdatedAt';
  static const clientSavedAt = 'clientSavedAt';
}

typedef OfflineActionHandler = Future<void> Function(OfflineAction action);

class OfflineActionQueue {
  OfflineActionQueue(this._box);

  final Box<String> _box;
  Future<void>? _activeDrain;
  static const _uuid = Uuid();
  static const syncedVisibilityWindow = Duration(minutes: 2);

  static Future<OfflineActionQueue> open() async {
    final box = await Hive.openBox<String>('offline_actions');
    return OfflineActionQueue(box);
  }

  Future<OfflineAction> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    DateTime? clientSavedAt,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final enrichedPayload = Map<String, dynamic>.from(payload);
    enrichedPayload[OfflineActionPayloadKeys.clientMutationId] ??= id;
    enrichedPayload[OfflineActionPayloadKeys.clientCreatedAt] ??= now
        .toIso8601String();
    enrichedPayload[OfflineActionPayloadKeys.clientUpdatedAt] ??= now
        .toIso8601String();
    enrichedPayload[OfflineActionPayloadKeys.clientSavedAt] ??=
        (clientSavedAt ?? now).toIso8601String();
    final action = OfflineAction(
      id: id,
      type: type,
      payload: enrichedPayload,
      createdAt: now,
    );
    await _box.put(action.id, jsonEncode(action.toMap()));
    if (kDebugMode && type == 'create_payment') {
      debugPrint(
        '[offline_queue.enqueue] type=$type id=${action.id} '
        'projectId=${enrichedPayload['projectId']} '
        'amount=${enrichedPayload['amount']} '
        'before=${enrichedPayload['projectTotalPaymentsBefore']} '
        'after=${enrichedPayload['projectTotalPaymentsAfter']}',
      );
    }
    return action;
  }

  Future<List<OfflineAction>> list({
    bool includeDeadLetters = false,
    bool includeExpiredSynced = false,
  }) async {
    final now = DateTime.now();
    final actions =
        _box.values
            .map(
              (raw) => OfflineAction.fromMap(
                jsonDecode(raw) as Map<String, dynamic>,
              ),
            )
            .where((action) {
              if (!includeDeadLetters &&
                  action.status == OfflineActionStatus.deadLetter) {
                return false;
              }
              if (action.status == OfflineActionStatus.synced) {
                if (includeExpiredSynced) {
                  return true;
                }
                final syncedAt = action.syncedAt;
                return syncedAt != null &&
                    now.difference(syncedAt) <= syncedVisibilityWindow;
              }
              return true;
            })
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (kDebugMode) {
      final paymentActions = actions
          .where((action) => action.type == 'create_payment')
          .map(
            (action) =>
                '${action.id}:${action.status}:project=${action.payload['projectId']}:'
                'amount=${action.payload['amount']}:'
                'before=${action.payload['projectTotalPaymentsBefore']}:'
                'after=${action.payload['projectTotalPaymentsAfter']}:'
                'syncedAt=${action.syncedAt?.toIso8601String()}:'
                'errorCode=${action.lastErrorCode}:'
                'error=${action.lastError}',
          )
          .toList();
      if (paymentActions.isNotEmpty) {
        debugPrint(
          '[offline_queue.list] includeExpiredSynced=$includeExpiredSynced '
          'payments=${paymentActions.join(' | ')}',
        );
      }
    }
    return actions;
  }

  Stream<List<OfflineAction>> watch({
    bool includeDeadLetters = false,
    bool includeExpiredSynced = false,
  }) async* {
    yield await list(
      includeDeadLetters: includeDeadLetters,
      includeExpiredSynced: includeExpiredSynced,
    );
    await for (final _ in _box.watch()) {
      yield await list(
        includeDeadLetters: includeDeadLetters,
        includeExpiredSynced: includeExpiredSynced,
      );
    }
  }

  Future<void> save(OfflineAction action) async {
    await _box.put(action.id, jsonEncode(action.toMap()));
    if (kDebugMode && action.type == 'create_payment') {
      debugPrint(
        '[offline_queue.save] type=${action.type} id=${action.id} '
        'status=${action.status} projectId=${action.payload['projectId']} '
        'amount=${action.payload['amount']} '
        'before=${action.payload['projectTotalPaymentsBefore']} '
        'after=${action.payload['projectTotalPaymentsAfter']} '
        'syncedAt=${action.syncedAt?.toIso8601String()} '
        'errorCode=${action.lastErrorCode} '
        'error=${action.lastError}',
      );
    }
  }

  Future<void> drain(
    OfflineActionHandler handler, {
    int maxRetries = 3,
    Duration retryBackoff = const Duration(minutes: 1),
  }) async {
    if (_activeDrain != null) {
      await _activeDrain;
      return;
    }

    final completer = Completer<void>();
    _activeDrain = completer.future;

    try {
      var blockedByFailure = false;
      while (!blockedByFailure) {
        final now = DateTime.now();
        final actions = (await list())
            .where((action) => action.status != OfflineActionStatus.synced)
            .toList();
        var processedAny = false;

        for (final action in actions) {
          if (action.nextAttemptAt != null &&
              action.nextAttemptAt!.isAfter(now)) {
            continue;
          }
          processedAny = true;
          try {
            if (kDebugMode && action.type == 'create_payment') {
              debugPrint(
                '[offline_queue.drain] processing id=${action.id} '
                'type=${action.type} status=${action.status} '
                'projectId=${action.payload['projectId']} '
                'amount=${action.payload['amount']} '
                'retryCount=${action.retryCount}',
              );
            }
            await handler(action);
            if (kDebugMode && action.type == 'create_payment') {
              debugPrint(
                '[offline_queue.drain] success id=${action.id} '
                'type=${action.type}',
              );
            }
            await save(
              action.copyWith(
                status: OfflineActionStatus.synced,
                syncedAt: DateTime.now(),
                clearLastError: true,
                clearNextAttemptAt: true,
              ),
            );
          } catch (error) {
            final details = SyncErrorClassifier.detailsFrom(error);
            if (kDebugMode && action.type == 'create_payment') {
              debugPrint(
                '[offline_queue.drain] failure id=${action.id} '
                'type=${action.type} projectId=${action.payload['projectId']} '
                'amount=${action.payload['amount']} '
                'retryCount=${action.retryCount} '
                'terminal=${SyncErrorClassifier.isTerminal(error)} '
                'code=${details.code} message=${details.message}',
              );
            }
            final nextRetryCount = action.retryCount + 1;
            if (SyncErrorClassifier.isTerminal(error) ||
                nextRetryCount >= maxRetries) {
              await save(
                action.copyWith(
                  retryCount: nextRetryCount,
                  lastError: details.message,
                  lastErrorCode: details.code,
                  status: OfflineActionStatus.deadLetter,
                  clearNextAttemptAt: true,
                ),
              );
            } else {
              await save(
                action.copyWith(
                  retryCount: nextRetryCount,
                  lastError: details.message,
                  lastErrorCode: details.code,
                  status: OfflineActionStatus.failed,
                  nextAttemptAt: DateTime.now().add(retryBackoff),
                ),
              );
            }
            // Stop on first failure to keep ordering guarantees.
            blockedByFailure = true;
            break;
          }
        }

        if (!processedAny) {
          break;
        }
      }
    } finally {
      completer.complete();
      _activeDrain = null;
    }
  }

  Future<int> pendingCount() async {
    final actions = await list();
    return actions
        .where(
          (action) =>
              action.status != OfflineActionStatus.deadLetter &&
              action.status != OfflineActionStatus.synced,
        )
        .length;
  }

  Future<List<OfflineAction>> deadLetters() async {
    final actions = await list(includeDeadLetters: true);
    return actions
        .where((action) => action.status == OfflineActionStatus.deadLetter)
        .toList();
  }
}
