import 'dart:async';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/pending_attachment_service.dart';
import 'package:buildtrack_app/core/utils/cash_collected.dart';
import 'package:buildtrack_app/core/utils/expense_items_total.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MutationResult {
  const MutationResult({this.id, this.queued = false});

  final String? id;
  final bool queued;
}

class WorkspaceBootstrapResult {
  const WorkspaceBootstrapResult({
    required this.workspaceId,
    required this.created,
    required this.setupCompleted,
  });

  factory WorkspaceBootstrapResult.fromMap(Map<String, dynamic> data) {
    return WorkspaceBootstrapResult(
      workspaceId: '${data['workspaceId'] ?? ''}'.trim(),
      created: data['created'] == true,
      setupCompleted: data['setupCompleted'] == true,
    );
  }

  final String workspaceId;
  final bool created;
  final bool setupCompleted;
}

abstract final class OfflineActionTypes {
  static const createProject = 'create_project';
  static const updateProject = 'update_project';
  static const archiveProject = 'archive_project';
  static const unarchiveProject = 'unarchive_project';
  static const deleteProject = 'delete_project';
  static const createExpense = 'create_expense';
  static const updateExpense = 'update_expense';
  static const archiveExpense = 'archive_expense';
  static const createPayment = 'create_payment';
  static const updatePayment = 'update_payment';
  static const archivePayment = 'archive_payment';
  static const createWorker = 'create_worker';
  static const updateWorker = 'update_worker';
  static const archiveWorker = 'archive_worker';
  static const createWorkerEntry = 'create_worker_entry';
  static const updateWorkerEntry = 'update_worker_entry';
  static const archiveWorkerEntry = 'archive_worker_entry';
  static const updateUserProfile = 'update_user_profile';
  static const updateUserSettings = 'update_user_settings';

  // Self-hosted backend only (spec 004, T080/T082): writes the app made
  // directly against Firestore now go through the queue to RPCs.
  static const upsertEntity = 'upsert_entity';
  static const touchEntityLastUsed = 'touch_entity_last_used';
  static const deleteEntity = 'delete_entity';
  static const upsertAccountingRecord = 'upsert_accounting_record';
  static const markNotificationsRead = 'mark_notifications_read';
}

/// Accounting-record family → the RPC that upserts it (contracts/rpc-api.md).
const accountingRecordRpcs = <String, String>{
  'worker': 'upsertWorkerAccountingRecord',
  'contractor': 'upsertContractorAccountingRecord',
  'equipment': 'upsertEquipmentAccountingRecord',
  'transport': 'upsertTransportProviderAccountingRecord',
};

/// Firestore collection → accounting-record family.
const accountingRecordKinds = <String, String>{
  'worker_accounting_records': 'worker',
  'contractor_accounting_records': 'contractor',
  'equipment_accounting_records': 'equipment',
  'transport_provider_accounting_records': 'transport',
};

class WorkspaceMutationService {
  const WorkspaceMutationService(this._client, this._queue, this._telemetry);

  final CallableClient _client;
  final OfflineActionQueue _queue;
  final AppTelemetry _telemetry;

  Future<MutationResult> createProject({
    required String workspaceId,
    required String name,
    required String clientName,
    double? contractValue,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    double completionPercentage = 0,
  }) async {
    final payload = {
      'workspaceId': workspaceId,
      'name': name,
      'clientName': clientName,
      'contractValue': contractValue,
      'startDate': startDate.toIso8601String(),
      'expectedEndDate': expectedEndDate?.toIso8601String(),
      'location': location ?? '',
      'description': description ?? '',
      'budgetLimit': budgetLimit,
      'completionPercentage': completionPercentage,
    };
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.createProject,
      payload: payload,
    );
  }

  Future<MutationResult> updateProject({
    required String workspaceId,
    required String projectId,
    required String name,
    required String clientName,
    double? contractValue,
    required double completionPercentage,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    String? status,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.updateProject,
      payload: {
        'workspaceId': workspaceId,
        'projectId': projectId,
        'name': name,
        'clientName': clientName,
        'contractValue': contractValue,
        'completionPercentage': completionPercentage,
        'startDate': startDate.toIso8601String(),
        'expectedEndDate': expectedEndDate?.toIso8601String(),
        'location': location ?? '',
        'description': description ?? '',
        'budgetLimit': budgetLimit,
        'status': status,
      },
    );
  }

  Future<MutationResult> createManualExpense({
    required String workspaceId,
    required String projectId,
    required String projectName,
    required String category,
    required double amount,
    required String currency,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    String inputMethod = 'manual',
    String? transcript,
    String? source,
    String? storagePath,
    double? projectTotalExpensesBefore,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, dynamic>>? items,
  }) async {
    final payload = {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'projectName': projectName,
      'category': category,
      'amount': items == null ? amount : expenseItemsTotal(items),
      'items': ?items,
      'currency': currency,
      'date': date.toIso8601String(),
      'notes': notes ?? '',
      'purpose': purpose ?? '',
      'description': description ?? notes ?? '',
      'supplierName': supplierName ?? '',
      'entityId': entityId ?? '',
      'entityName': entityName ?? '',
      'entityType': entityType ?? 'supplier',
      'paymentMethod': paymentMethod ?? '',
      'paymentStatus': paymentStatus ?? 'unpaid',
      'inputMethod': inputMethod,
      'transcript': transcript ?? '',
      'source': source ?? '',
      'storagePath': storagePath ?? '',
      'projectTotalExpensesBefore': projectTotalExpensesBefore,
    };
    if (attachments != null) {
      payload['attachments'] = attachments;
    }

    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.createExpense,
      payload: payload,
    );
  }

  Future<MutationResult> archiveExpense({
    required String workspaceId,
    required String expenseId,
    String? projectId,
    String? category,
    double? amount,
    DateTime? date,
  }) async {
    final payload = <String, dynamic>{
      'workspaceId': workspaceId,
      'expenseId': expenseId,
    };
    if (projectId != null) payload['projectId'] = projectId;
    if (category != null) payload['category'] = category;
    if (amount != null) payload['amount'] = amount;
    if (date != null) payload['date'] = date.toIso8601String();
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.archiveExpense,
      payload: payload,
    );
  }

  Future<MutationResult> archiveProject({
    required String workspaceId,
    required String projectId,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.archiveProject,
      payload: {'workspaceId': workspaceId, 'projectId': projectId},
    );
  }

  Future<MutationResult> unarchiveProject({
    required String workspaceId,
    required String projectId,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.unarchiveProject,
      payload: {'workspaceId': workspaceId, 'projectId': projectId},
    );
  }

  Future<MutationResult> updateExpense({
    required String workspaceId,
    required String expenseId,
    required String projectId,
    required String category,
    required double amount,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    List<Map<String, dynamic>>? attachments,
    double? previousAmount,
    DateTime? previousDate,
    String? previousCategory,
    List<Map<String, dynamic>>? items,
  }) {
    final payload = {
      'workspaceId': workspaceId,
      'expenseId': expenseId,
      'projectId': projectId,
      'category': category,
      'amount': items == null ? amount : expenseItemsTotal(items),
      'date': date.toIso8601String(),
      'notes': notes ?? '',
      'purpose': purpose ?? '',
      // The server saves the title on update (feature 005), so a missing
      // description must stay missing instead of copying the notes over it.
      'description': ?description,
      'items': ?items,
      'supplierName': supplierName ?? '',
      'entityId': entityId ?? '',
      'entityName': entityName ?? '',
      'entityType': entityType ?? 'supplier',
      'paymentMethod': paymentMethod ?? '',
      'paymentStatus': paymentStatus ?? 'unpaid',
      'previousAmount': previousAmount,
      'previousDate': previousDate?.toIso8601String(),
      'previousCategory': previousCategory,
    };
    if (attachments != null) {
      payload['attachments'] = attachments;
    }

    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.updateExpense,
      payload: payload,
    );
  }

  Future<MutationResult> createPayment({
    required String workspaceId,
    required String projectId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? paymentStatus,
    double? paidAmount,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    double? projectTotalPaymentsBefore,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final collected = cashCollectedAmount(
      amount: amount,
      paymentStatus: paymentStatus ?? 'paid',
      paidAmount: paidAmount,
    );
    final projectTotalPaymentsAfter = projectTotalPaymentsBefore == null
        ? null
        : projectTotalPaymentsBefore + collected;
    final payload = {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'amount': amount,
      'date': date.toIso8601String(),
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus ?? 'paid',
      'paidAmount': paidAmount,
      'description': description ?? notes ?? '',
      'notes': notes ?? '',
      'entityId': entityId ?? '',
      'entityName': entityName ?? '',
      'entityType': entityType ?? 'other',
      'projectTotalPaymentsBefore': projectTotalPaymentsBefore,
      'projectTotalPaymentsAfter': projectTotalPaymentsAfter,
    };
    if (attachments != null) {
      payload['attachments'] = attachments;
    }
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.createPayment,
      payload: payload,
    );
  }

  Future<MutationResult> archivePayment({
    required String workspaceId,
    required String paymentId,
    String? projectId,
    double? amount,
    String? paymentStatus,
    double? paidAmount,
    DateTime? date,
  }) async {
    final payload = <String, dynamic>{
      'workspaceId': workspaceId,
      'paymentId': paymentId,
    };
    if (projectId != null) payload['projectId'] = projectId;
    if (amount != null) payload['amount'] = amount;
    if (paymentStatus != null) payload['paymentStatus'] = paymentStatus;
    if (paidAmount != null) payload['paidAmount'] = paidAmount;
    if (date != null) payload['date'] = date.toIso8601String();
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.archivePayment,
      payload: payload,
    );
  }

  Future<MutationResult> updatePayment({
    required String workspaceId,
    required String paymentId,
    required String projectId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? paymentStatus,
    String? previousPaymentStatus,
    double? paidAmount,
    double? previousPaidAmount,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    double? previousAmount,
    DateTime? previousDate,
    List<Map<String, dynamic>>? attachments,
  }) {
    final payload = {
      'workspaceId': workspaceId,
      'paymentId': paymentId,
      'projectId': projectId,
      'amount': amount,
      'date': date.toIso8601String(),
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus ?? 'paid',
      'previousPaymentStatus': previousPaymentStatus,
      'paidAmount': paidAmount,
      'previousPaidAmount': previousPaidAmount,
      'description': description ?? notes ?? '',
      'notes': notes ?? '',
      'entityId': entityId ?? '',
      'entityName': entityName ?? '',
      'entityType': entityType ?? 'other',
      'previousAmount': previousAmount,
      'previousDate': previousDate?.toIso8601String(),
    };
    if (attachments != null) {
      payload['attachments'] = attachments;
    }
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.updatePayment,
      payload: payload,
    );
  }

  Future<MutationResult> createWorkerEntry({
    required String workspaceId,
    required String workerId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
    List<Map<String, dynamic>>? attachments,
    double? projectTotalExpensesBefore,
  }) async {
    final payload = {
      'workspaceId': workspaceId,
      'workerId': workerId,
      'projectId': projectId,
      'daysWorked': daysWorked,
      'dailyWage': dailyWage,
      'date': date.toIso8601String(),
      'notes': notes ?? '',
      'projectTotalExpensesBefore': projectTotalExpensesBefore,
    };
    if (attachments != null) {
      payload['attachments'] = attachments;
    }

    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.createWorkerEntry,
      payload: payload,
    );
  }

  Future<MutationResult> archiveWorkerEntry({
    required String workspaceId,
    required String entryId,
    String? projectId,
    double? daysWorked,
    double? dailyWage,
    double? totalCost,
    DateTime? date,
  }) async {
    final payload = <String, dynamic>{
      'workspaceId': workspaceId,
      'entryId': entryId,
    };
    if (projectId != null) payload['projectId'] = projectId;
    if (daysWorked != null) payload['daysWorked'] = daysWorked;
    if (dailyWage != null) payload['dailyWage'] = dailyWage;
    if (totalCost != null) payload['totalCost'] = totalCost;
    if (date != null) payload['date'] = date.toIso8601String();
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.archiveWorkerEntry,
      payload: payload,
    );
  }

  Future<void> deleteProjectCascade({
    required String workspaceId,
    required String projectId,
  }) async {
    await _enqueueForBackgroundSync(
      type: OfflineActionTypes.deleteProject,
      payload: {'workspaceId': workspaceId, 'projectId': projectId},
    );
  }

  Future<void> updateWorkerEntry({
    required String workspaceId,
    required String entryId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
    String? previousProjectId,
    double? previousDaysWorked,
    double? previousDailyWage,
    double? previousTotalCost,
    DateTime? previousDate,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final payload = <String, dynamic>{
      'workspaceId': workspaceId,
      'entryId': entryId,
      'projectId': projectId,
      'daysWorked': daysWorked,
      'dailyWage': dailyWage,
      'date': date.toIso8601String(),
      'notes': notes ?? '',
      'previousProjectId': previousProjectId,
      'previousDaysWorked': previousDaysWorked,
      'previousDailyWage': previousDailyWage,
      'previousTotalCost': previousTotalCost,
      'previousDate': previousDate?.toIso8601String(),
    };
    if (attachments != null) {
      payload['attachments'] = attachments;
    }

    await _enqueueForBackgroundSync(
      type: OfflineActionTypes.updateWorkerEntry,
      payload: payload,
    );
  }

  Future<MutationResult> createWorker({
    required String workspaceId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    String? status,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.createWorker,
      payload: {
        'workspaceId': workspaceId,
        'name': name,
        'phoneNumber': phoneNumber,
        'dailyWage': dailyWage,
        'billingType': billingType,
        'workerType': workerType ?? '',
        'notes': notes ?? '',
        'status': status ?? 'active',
      },
    );
  }

  Future<MutationResult> updateWorker({
    required String workspaceId,
    required String workerId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    String? status,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.updateWorker,
      payload: {
        'workspaceId': workspaceId,
        'workerId': workerId,
        'name': name,
        'phoneNumber': phoneNumber,
        'dailyWage': dailyWage,
        'billingType': billingType,
        'workerType': workerType ?? '',
        'notes': notes ?? '',
        'status': status,
      },
    );
  }

  Future<MutationResult> archiveWorker({
    required String workspaceId,
    required String workerId,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.archiveWorker,
      payload: {'workspaceId': workspaceId, 'workerId': workerId},
    );
  }

  Future<void> updateUserProfile({
    required String fullName,
    String? photoUrl,
    String? defaultCurrency,
    bool? riskAlertsEnabled,
  }) async {
    await _enqueueForBackgroundSync(
      type: OfflineActionTypes.updateUserProfile,
      payload: {
        'fullName': fullName,
        'photoUrl': photoUrl,
        'defaultCurrency': defaultCurrency,
        'riskAlertsEnabled': riskAlertsEnabled,
      },
    );
  }

  Future<MutationResult> updateUserSettings({
    required String userId,
    String? defaultCurrency,
    bool? riskAlertsEnabled,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.updateUserSettings,
      payload: {
        'userId': userId,
        'defaultCurrency': defaultCurrency,
        'riskAlertsEnabled': riskAlertsEnabled,
      },
    );
  }

  Future<void> inviteMemberByEmail({
    required String workspaceId,
    required String email,
    String role = 'member',
  }) {
    return _client.call<void>(
      functionName: 'inviteMemberByEmail',
      payload: {'workspaceId': workspaceId, 'email': email, 'role': role},
      parseResult: (_) {},
      defaultErrorMessage: 'Failed to invite member.',
    );
  }

  /// Owner only; online (the name is shown everywhere, so no queued rename).
  Future<void> updateWorkspaceName({
    required String workspaceId,
    required String name,
  }) {
    return _client.call<void>(
      functionName: 'updateWorkspaceName',
      payload: {'workspaceId': workspaceId, 'name': name},
      parseResult: (_) {},
      defaultErrorMessage: 'Failed to rename the workspace.',
    );
  }

  Future<WorkspaceBootstrapResult> ensureUserWorkspaceBootstrap() {
    return _client.call<WorkspaceBootstrapResult>(
      functionName: 'ensureUserWorkspaceBootstrap',
      payload: const {},
      parseResult: (result) {
        final data = Map<String, dynamic>.from(result as Map);
        return WorkspaceBootstrapResult.fromMap(data);
      },
      defaultErrorMessage: 'Failed to set up your workspace.',
    );
  }

  Future<WorkspaceBootstrapResult> completeInitialWorkspaceSetup({
    required String workspaceId,
    required String workspaceName,
    required String defaultCurrency,
  }) {
    return _client.call<WorkspaceBootstrapResult>(
      functionName: 'completeInitialWorkspaceSetup',
      payload: {
        'workspaceId': workspaceId,
        'workspaceName': workspaceName,
        'defaultCurrency': defaultCurrency,
      },
      parseResult: (result) {
        final data = Map<String, dynamic>.from(result as Map);
        return WorkspaceBootstrapResult.fromMap({...data, 'created': false});
      },
      defaultErrorMessage: 'Failed to complete workspace setup.',
    );
  }

  Future<String> createWorkspace({
    required String sourceWorkspaceId,
    required String workspaceName,
    required String defaultCurrency,
  }) {
    return _client.call<String>(
      functionName: 'createWorkspace',
      payload: {
        'sourceWorkspaceId': sourceWorkspaceId,
        'workspaceName': workspaceName,
        'defaultCurrency': defaultCurrency,
      },
      parseResult: (result) {
        final data = Map<String, dynamic>.from(result as Map);
        return '${data['workspaceId'] ?? ''}'.trim();
      },
      defaultErrorMessage: 'Failed to create workspace.',
    );
  }

  Future<String> setActiveWorkspace({required String workspaceId}) {
    return _client.call<String>(
      functionName: 'setActiveWorkspace',
      payload: {'workspaceId': workspaceId},
      parseResult: (result) {
        final data = Map<String, dynamic>.from(result as Map);
        return '${data['workspaceId'] ?? ''}'.trim();
      },
      defaultErrorMessage: 'Failed to switch workspace.',
    );
  }

  Future<void> updateWorkspaceMemberRole({
    required String workspaceId,
    required String userId,
    required String role,
  }) {
    return _client.call<void>(
      functionName: 'updateWorkspaceMemberRole',
      payload: {'workspaceId': workspaceId, 'userId': userId, 'role': role},
      parseResult: (_) {},
      defaultErrorMessage: 'Failed to update workspace member.',
    );
  }

  Future<void> removeWorkspaceMember({
    required String workspaceId,
    required String userId,
  }) {
    return _client.call<void>(
      functionName: 'removeWorkspaceMember',
      payload: {'workspaceId': workspaceId, 'userId': userId},
      parseResult: (_) {},
      defaultErrorMessage: 'Failed to remove workspace member.',
    );
  }

  Future<OfflineActionOutcome> processQueuedAction(OfflineAction action) async {
    await _telemetry.log('offline_sync.process', {
      'type': action.type,
      'retry_count': action.retryCount,
    });
    if (await _isStaleLastSavedUpdate(action)) {
      final targetId = _conflictTargetId(action);
      await _telemetry.log('offline_sync.skipped_stale_update', {
        'type': action.type,
        'target': targetId,
      });
      return OfflineActionOutcome.skippedNewerVersion(targetId: targetId);
    }
    await _applyQueuedAction(action);
    return OfflineActionOutcome.applied(targetId: _conflictTargetId(action));
  }

  /// Every call carries the action id as its idempotency key (spec 004,
  /// T080): a replay after a lost response returns the stored result
  /// instead of creating a second record.
  Future<void> _applyQueuedAction(OfflineAction action) async {
    switch (action.type) {
      case OfflineActionTypes.createProject:
        final result = await _client.call<Map<String, dynamic>>(
          functionName: 'createProjectWithQuota',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to create project.',
        );
        final serverId = '${result['id'] ?? ''}'.trim();
        if (serverId.isNotEmpty) {
          await _queue.remapPendingProjectIds(
            pendingId: 'pending_${action.id}',
            serverId: serverId,
          );
        }
        return;
      case OfflineActionTypes.updateProject:
        await _client.call<void>(
          functionName: 'updateProject',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update project.',
        );
        return;
      case OfflineActionTypes.archiveProject:
        await _client.call<void>(
          functionName: 'archiveProject',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive project.',
        );
        return;
      case OfflineActionTypes.unarchiveProject:
        await _client.call<void>(
          functionName: 'unarchiveProject',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to unarchive project.',
        );
        return;
      case OfflineActionTypes.deleteProject:
        await _client.call<void>(
          functionName: 'deleteProjectCascade',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to delete project.',
        );
        return;
      case OfflineActionTypes.createExpense:
        await _client.call<Map<String, dynamic>>(
          functionName: 'createExpenseWithQuota',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to save expense.',
        );
        return;
      case OfflineActionTypes.updateExpense:
        await _client.call<void>(
          functionName: 'updateExpense',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update expense.',
        );
        return;
      case OfflineActionTypes.archiveExpense:
        await _client.call<void>(
          functionName: 'archiveExpenseWithQuotaRefund',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive expense.',
        );
        return;
      case OfflineActionTypes.createPayment:
        await _client.call<Map<String, dynamic>>(
          functionName: 'createPaymentWithQuota',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to save payment.',
        );
        return;
      case OfflineActionTypes.updatePayment:
        await _client.call<void>(
          functionName: 'updatePayment',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update payment.',
        );
        return;
      case OfflineActionTypes.archivePayment:
        await _client.call<void>(
          functionName: 'archivePaymentWithQuotaRefund',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive payment.',
        );
        return;
      case OfflineActionTypes.createWorkerEntry:
        await _client.call<Map<String, dynamic>>(
          functionName: 'createWorkerEntryWithQuota',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to save worker entry.',
        );
        return;
      case OfflineActionTypes.createWorker:
        await _client.call<Map<String, dynamic>>(
          functionName: 'createWorker',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to save worker.',
        );
        return;
      case OfflineActionTypes.updateWorker:
        await _client.call<void>(
          functionName: 'updateWorker',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update worker.',
        );
        return;
      case OfflineActionTypes.archiveWorker:
        await _client.call<void>(
          functionName: 'archiveWorker',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive worker.',
        );
        return;
      case OfflineActionTypes.updateWorkerEntry:
        await _client.call<void>(
          functionName: 'updateWorkerEntry',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update worker entry.',
        );
        return;
      case OfflineActionTypes.archiveWorkerEntry:
        await _client.call<void>(
          functionName: 'archiveWorkerEntryWithQuotaRefund',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive worker entry.',
        );
        return;
      case OfflineActionTypes.updateUserProfile:
        await _client.call<void>(
          functionName: 'updateUserProfile',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update profile.',
        );
        return;
      case OfflineActionTypes.updateUserSettings:
        await _client.call<void>(
          functionName: 'updateUserSettings',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update settings.',
        );
        return;
      case OfflineActionTypes.upsertEntity:
        await _client.call<void>(
          functionName: 'upsertEntity',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to save contact.',
        );
        return;
      case OfflineActionTypes.touchEntityLastUsed:
        await _client.call<void>(
          functionName: 'touchEntityLastUsed',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update contact.',
        );
        return;
      case OfflineActionTypes.deleteEntity:
        await _client.call<void>(
          functionName: 'deleteEntity',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to delete contact.',
        );
        return;
      case OfflineActionTypes.upsertAccountingRecord:
        final kind = '${action.payload['kind'] ?? ''}';
        final functionName = accountingRecordRpcs[kind];
        final record = action.payload['record'];
        if (functionName == null || record is! Map) {
          throw CallableClientException(
            'Unknown accounting record kind: $kind',
            code: 'invalid-argument',
          );
        }
        await _client.call<void>(
          functionName: functionName,
          idempotencyKey: action.id,
          payload: Map<String, dynamic>.from(record),
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to save accounting record.',
        );
        return;
      case OfflineActionTypes.markNotificationsRead:
        await _client.call<void>(
          functionName: 'markNotificationsRead',
          idempotencyKey: action.id,
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update notifications.',
        );
        return;
      case OfflineActionQueueTypes.attachmentUpload:
        final rawAttachment = action.payload['attachment'];
        if (rawAttachment is Map) {
          final pending = await PendingAttachmentService.open();
          await pending.savePending(
            workspaceId: '${action.payload['workspaceId'] ?? ''}',
            ownerType: '${action.payload['ownerType'] ?? ''}',
            ownerId: '${action.payload['ownerId'] ?? ''}',
            attachment: Attachment.fromMap(
              Map<String, dynamic>.from(rawAttachment),
            ),
          );
        }
        return;
      default:
        throw UnsupportedError('Unsupported offline action: ${action.type}');
    }
  }

  /// Queues a contact create/edit (`upsertEntity`). [payload] must be JSON-safe
  /// and carry the entity `id` the app already shows.
  Future<MutationResult> upsertEntity(Map<String, dynamic> payload) =>
      _enqueueForBackgroundSync(
        type: OfflineActionTypes.upsertEntity,
        payload: payload,
      );

  Future<MutationResult> touchEntityLastUsed({
    required String workspaceId,
    required String entityId,
  }) => _enqueueForBackgroundSync(
    type: OfflineActionTypes.touchEntityLastUsed,
    payload: {'workspaceId': workspaceId, 'entityId': entityId},
  );

  Future<MutationResult> deleteEntity({
    required String workspaceId,
    required String entityId,
  }) => _enqueueForBackgroundSync(
    type: OfflineActionTypes.deleteEntity,
    payload: {'workspaceId': workspaceId, 'entityId': entityId},
  );

  /// Queues an accounting-record upsert. [kind] is a key of
  /// [accountingRecordRpcs]; [record] must be JSON-safe (ISO dates).
  Future<MutationResult> upsertAccountingRecord({
    required String kind,
    required Map<String, dynamic> record,
  }) {
    if (!accountingRecordRpcs.containsKey(kind)) {
      throw ArgumentError.value(kind, 'kind', 'Unknown accounting record kind');
    }
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.upsertAccountingRecord,
      payload: {'kind': kind, 'record': record},
    );
  }

  Future<MutationResult> markNotificationsRead(Iterable<String> ids) =>
      _enqueueForBackgroundSync(
        type: OfflineActionTypes.markNotificationsRead,
        payload: {'notificationIds': ids.toList(growable: false)},
      );

  Future<MutationResult> _enqueueForBackgroundSync({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final action = await _queue.enqueue(type: type, payload: payload);
    await _enqueuePendingAttachmentUploads(
      actionType: type,
      sourceAction: action,
      payload: payload,
    );
    await _telemetry.log('offline_sync.enqueued', {'type': type});
    unawaited(_tryDrainInBackground());
    return MutationResult(id: action.id, queued: true);
  }

  Future<void> _enqueuePendingAttachmentUploads({
    required String actionType,
    required OfflineAction sourceAction,
    required Map<String, dynamic> payload,
  }) async {
    final ownerType = _attachmentOwnerTypeFor(actionType);
    if (ownerType == null) {
      return;
    }

    final attachments = payload['attachments'];
    if (attachments is! Iterable) {
      return;
    }

    final workspaceId = payload['workspaceId'] as String?;
    if (workspaceId == null || workspaceId.isEmpty) {
      return;
    }

    final ownerId = _attachmentOwnerIdFor(
      actionType: actionType,
      sourceActionId: sourceAction.id,
      payload: payload,
    );
    for (final rawAttachment in attachments) {
      if (rawAttachment is! Map) {
        continue;
      }
      final attachment = Map<String, dynamic>.from(rawAttachment);
      final localPath = (attachment['localPath'] as String?)?.trim() ?? '';
      final uploadStatus =
          (attachment['uploadStatus'] as String?)?.trim().toLowerCase() ?? '';
      if (localPath.isEmpty || uploadStatus == 'uploaded') {
        continue;
      }

      await _queue.enqueue(
        type: OfflineActionQueueTypes.attachmentUpload,
        payload: {
          OfflineActionPayloadKeys.workspaceId: workspaceId,
          OfflineActionPayloadKeys.ownerType: ownerType,
          OfflineActionPayloadKeys.ownerId: ownerId,
          OfflineActionPayloadKeys.attachment: attachment,
          'sourceActionId': sourceAction.id,
          'sourceActionType': actionType,
        },
      );
    }
  }

  String? _attachmentOwnerTypeFor(String actionType) {
    switch (actionType) {
      case OfflineActionTypes.createExpense:
      case OfflineActionTypes.updateExpense:
        return 'expense';
      case OfflineActionTypes.createPayment:
      case OfflineActionTypes.updatePayment:
        return 'payment';
      case OfflineActionTypes.createWorkerEntry:
      case OfflineActionTypes.updateWorkerEntry:
        return 'worker_entry';
      default:
        return null;
    }
  }

  String _attachmentOwnerIdFor({
    required String actionType,
    required String sourceActionId,
    required Map<String, dynamic> payload,
  }) {
    switch (actionType) {
      case OfflineActionTypes.updateExpense:
        return (payload['expenseId'] as String?) ?? sourceActionId;
      case OfflineActionTypes.updatePayment:
        return (payload['paymentId'] as String?) ?? sourceActionId;
      case OfflineActionTypes.updateWorkerEntry:
        return (payload['entryId'] as String?) ?? sourceActionId;
      default:
        return sourceActionId;
    }
  }

  Future<void> _tryDrainInBackground() async {
    try {
      if (await _shouldQueueOffline()) {
        return;
      }
      await _queue.drain(processQueuedAction);
    } catch (error, stackTrace) {
      await _telemetry.log('offline_sync.drain_deferred', {
        'error': error.toString(),
      });
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'workspace mutation service',
          context: ErrorDescription('while draining queued mutations'),
        ),
      );
    }
  }

  Future<bool> _shouldQueueOffline() async {
    final status = await Connectivity().checkConnectivity();
    return status.any((result) => result == ConnectivityResult.none);
  }

  Future<bool> _isStaleLastSavedUpdate(OfflineAction action) async {
    final targetId = _conflictTargetId(action);
    if (targetId == null || targetId.isEmpty) {
      return false;
    }
    final savedAt = _clientSavedAt(action);
    if (savedAt == null) {
      return false;
    }

    final actions = await _queue.list(
      includeDeadLetters: true,
      includeExpiredSynced: true,
    );
    return actions.any((candidate) {
      if (candidate.id == action.id ||
          candidate.type != action.type ||
          candidate.status == OfflineActionStatus.deadLetter ||
          _conflictTargetId(candidate) != targetId) {
        return false;
      }
      final candidateSavedAt = _clientSavedAt(candidate);
      return candidateSavedAt != null && candidateSavedAt.isAfter(savedAt);
    });
  }

  DateTime? _clientSavedAt(OfflineAction action) {
    final raw = action.payload[OfflineActionPayloadKeys.clientSavedAt];
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  String? _conflictTargetId(OfflineAction action) {
    switch (action.type) {
      case OfflineActionTypes.updateProject:
      case OfflineActionTypes.archiveProject:
      case OfflineActionTypes.unarchiveProject:
      case OfflineActionTypes.deleteProject:
        return action.payload['projectId'] as String?;
      case OfflineActionTypes.updateExpense:
      case OfflineActionTypes.archiveExpense:
        return action.payload['expenseId'] as String?;
      case OfflineActionTypes.updatePayment:
      case OfflineActionTypes.archivePayment:
        return action.payload['paymentId'] as String?;
      case OfflineActionTypes.updateWorker:
      case OfflineActionTypes.archiveWorker:
        return action.payload['workerId'] as String?;
      case OfflineActionTypes.updateWorkerEntry:
      case OfflineActionTypes.archiveWorkerEntry:
        return action.payload['entryId'] as String?;
      case OfflineActionTypes.updateUserProfile:
      case OfflineActionTypes.updateUserSettings:
        return action.payload['userId'] as String?;
      default:
        return null;
    }
  }
}

final workspaceMutationServiceProvider = Provider<WorkspaceMutationService>((
  ref,
) {
  return WorkspaceMutationService(
    ref.watch(callableClientProvider),
    ref.watch(offlineActionQueueProvider),
    ref.watch(appTelemetryProvider),
  );
});
