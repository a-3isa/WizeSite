import 'dart:async';

import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MutationResult {
  const MutationResult({this.id, this.queued = false});

  final String? id;
  final bool queued;
}

abstract final class OfflineActionTypes {
  static const createProject = 'create_project';
  static const createExpense = 'create_expense';
  static const archiveExpense = 'archive_expense';
  static const createPayment = 'create_payment';
  static const archivePayment = 'archive_payment';
  static const createWorkerEntry = 'create_worker_entry';
  static const archiveWorkerEntry = 'archive_worker_entry';
}

class WorkspaceMutationService {
  const WorkspaceMutationService(this._client, this._queue);

  final CallableClient _client;
  final OfflineActionQueue _queue;

  Future<MutationResult> createProject({
    required String workspaceId,
    required String name,
    required String clientName,
    required double contractValue,
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

  Future<MutationResult> createManualExpense({
    required String workspaceId,
    required String projectId,
    required String projectName,
    required String category,
    required double amount,
    required String currency,
    required DateTime date,
    String? notes,
    String? supplierName,
    String? paymentMethod,
  }) async {
    final payload = {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'projectName': projectName,
      'category': category,
      'amount': amount,
      'currency': currency,
      'date': date.toIso8601String(),
      'notes': notes ?? '',
      'supplierName': supplierName ?? '',
      'paymentMethod': paymentMethod ?? '',
      'inputMethod': 'manual',
    };

    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.createExpense,
      payload: payload,
    );
  }

  Future<MutationResult> archiveExpense({
    required String workspaceId,
    required String expenseId,
  }) async {
    final payload = {'workspaceId': workspaceId, 'expenseId': expenseId};
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.archiveExpense,
      payload: payload,
    );
  }

  Future<MutationResult> createPayment({
    required String workspaceId,
    required String projectId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? notes,
  }) async {
    final payload = {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'amount': amount,
      'date': date.toIso8601String(),
      'paymentMethod': paymentMethod,
      'notes': notes ?? '',
    };

    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.createPayment,
      payload: payload,
    );
  }

  Future<MutationResult> archivePayment({
    required String workspaceId,
    required String paymentId,
  }) async {
    final payload = {'workspaceId': workspaceId, 'paymentId': paymentId};
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.archivePayment,
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
  }) async {
    final payload = {
      'workspaceId': workspaceId,
      'workerId': workerId,
      'projectId': projectId,
      'daysWorked': daysWorked,
      'dailyWage': dailyWage,
      'date': date.toIso8601String(),
      'notes': notes ?? '',
    };

    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.createWorkerEntry,
      payload: payload,
    );
  }

  Future<MutationResult> archiveWorkerEntry({
    required String workspaceId,
    required String entryId,
  }) async {
    final payload = {'workspaceId': workspaceId, 'entryId': entryId};
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.archiveWorkerEntry,
      payload: payload,
    );
  }

  Future<void> deleteProjectCascade({
    required String workspaceId,
    required String projectId,
  }) {
    return _client.call<void>(
      functionName: 'deleteProjectCascade',
      payload: {'workspaceId': workspaceId, 'projectId': projectId},
      parseResult: (_) {},
      defaultErrorMessage: 'Failed to delete project.',
    );
  }

  Future<void> updateUserProfile({
    required String fullName,
    String? photoUrl,
    String? defaultCurrency,
    bool? riskAlertsEnabled,
  }) {
    return _client.call<void>(
      functionName: 'updateUserProfile',
      payload: {
        'fullName': fullName,
        'photoUrl': photoUrl,
        'defaultCurrency': defaultCurrency,
        'riskAlertsEnabled': riskAlertsEnabled,
      },
      parseResult: (_) {},
      defaultErrorMessage: 'Failed to update profile.',
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

  Future<void> processQueuedAction(OfflineAction action) async {
    switch (action.type) {
      case OfflineActionTypes.createProject:
        await _client.call<Map<String, dynamic>>(
          functionName: 'createProjectWithQuota',
          httpFunctionName: 'createProjectWithQuotaHttp',
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to create project.',
        );
        return;
      case OfflineActionTypes.createExpense:
        await _client.call<Map<String, dynamic>>(
          functionName: 'createExpenseWithQuota',
          httpFunctionName: 'createExpenseWithQuotaHttp',
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to save expense.',
        );
        return;
      case OfflineActionTypes.archiveExpense:
        await _client.call<void>(
          functionName: 'archiveExpenseWithQuotaRefund',
          httpFunctionName: 'archiveExpenseWithQuotaRefundHttp',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive expense.',
        );
        return;
      case OfflineActionTypes.createPayment:
        await _client.call<Map<String, dynamic>>(
          functionName: 'createPaymentWithQuota',
          httpFunctionName: 'createPaymentWithQuotaHttp',
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to save payment.',
        );
        return;
      case OfflineActionTypes.archivePayment:
        await _client.call<void>(
          functionName: 'archivePaymentWithQuotaRefund',
          httpFunctionName: 'archivePaymentWithQuotaRefundHttp',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive payment.',
        );
        return;
      case OfflineActionTypes.createWorkerEntry:
        await _client.call<Map<String, dynamic>>(
          functionName: 'createWorkerEntryWithQuota',
          httpFunctionName: 'createWorkerEntryWithQuotaHttp',
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to save worker entry.',
        );
        return;
      case OfflineActionTypes.archiveWorkerEntry:
        await _client.call<void>(
          functionName: 'archiveWorkerEntryWithQuotaRefund',
          httpFunctionName: 'archiveWorkerEntryWithQuotaRefundHttp',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive worker entry.',
        );
        return;
      default:
        throw UnsupportedError('Unsupported offline action: ${action.type}');
    }
  }

  Future<MutationResult> _enqueueForBackgroundSync({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    await _queue.enqueue(type: type, payload: payload);
    unawaited(_tryDrainInBackground());
    return const MutationResult(queued: true);
  }

  Future<void> _tryDrainInBackground() async {
    if (await _shouldQueueOffline()) {
      return;
    }
    await _queue.drain(processQueuedAction);
  }

  Future<bool> _shouldQueueOffline() async {
    final status = await Connectivity().checkConnectivity();
    return status.any((result) => result == ConnectivityResult.none);
  }
}

final workspaceMutationServiceProvider = Provider<WorkspaceMutationService>((
  ref,
) {
  return WorkspaceMutationService(
    ref.watch(callableClientProvider),
    ref.watch(offlineActionQueueProvider),
  );
});
