import 'dart:async';

import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/app_telemetry.dart';
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
  static const updateProject = 'update_project';
  static const archiveProject = 'archive_project';
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
}

class WorkspaceMutationService {
  const WorkspaceMutationService(this._client, this._queue, this._telemetry);

  final CallableClient _client;
  final OfflineActionQueue _queue;
  final AppTelemetry _telemetry;

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

  Future<MutationResult> updateProject({
    required String workspaceId,
    required String projectId,
    required String name,
    required String clientName,
    required double contractValue,
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
    String? supplierName,
    String? paymentMethod,
    String inputMethod = 'manual',
    String? transcript,
    String? source,
    String? storagePath,
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
      'inputMethod': inputMethod,
      'transcript': transcript ?? '',
      'source': source ?? '',
      'storagePath': storagePath ?? '',
    };

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
      payload: {
        'workspaceId': workspaceId,
        'projectId': projectId,
      },
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
    String? supplierName,
    String? paymentMethod,
    double? previousAmount,
    DateTime? previousDate,
    String? previousCategory,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.updateExpense,
      payload: {
        'workspaceId': workspaceId,
        'expenseId': expenseId,
        'projectId': projectId,
        'category': category,
        'amount': amount,
        'date': date.toIso8601String(),
        'notes': notes ?? '',
        'supplierName': supplierName ?? '',
        'paymentMethod': paymentMethod ?? '',
        'previousAmount': previousAmount,
        'previousDate': previousDate?.toIso8601String(),
        'previousCategory': previousCategory,
      },
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
    String? projectId,
    double? amount,
    DateTime? date,
  }) async {
    final payload = <String, dynamic>{
      'workspaceId': workspaceId,
      'paymentId': paymentId,
    };
    if (projectId != null) payload['projectId'] = projectId;
    if (amount != null) payload['amount'] = amount;
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
    String? notes,
    double? previousAmount,
    DateTime? previousDate,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.updatePayment,
      payload: {
        'workspaceId': workspaceId,
        'paymentId': paymentId,
        'projectId': projectId,
        'amount': amount,
        'date': date.toIso8601String(),
        'paymentMethod': paymentMethod,
        'notes': notes ?? '',
        'previousAmount': previousAmount,
        'previousDate': previousDate?.toIso8601String(),
      },
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
  }) {
    return _client.call<void>(
      functionName: 'deleteProjectCascade',
      payload: {'workspaceId': workspaceId, 'projectId': projectId},
      parseResult: (_) {},
      defaultErrorMessage: 'Failed to delete project.',
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
  }) async {
    await _enqueueForBackgroundSync(
      type: OfflineActionTypes.updateWorkerEntry,
      payload: {
        'workspaceId': workspaceId,
        'entryId': entryId,
        'projectId': projectId,
        'daysWorked': daysWorked,
        'dailyWage': dailyWage,
        'date': date.toIso8601String(),
        'notes': notes ?? '',
      },
    );
  }

  Future<MutationResult> createWorker({
    required String workspaceId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    String? workerType,
    String? notes,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.createWorker,
      payload: {
        'workspaceId': workspaceId,
        'name': name,
        'phoneNumber': phoneNumber,
        'dailyWage': dailyWage,
        'workerType': workerType ?? '',
        'notes': notes ?? '',
      },
    );
  }

  Future<MutationResult> updateWorker({
    required String workspaceId,
    required String workerId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    String? workerType,
    String? notes,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.updateWorker,
      payload: {
        'workspaceId': workspaceId,
        'workerId': workerId,
        'name': name,
        'phoneNumber': phoneNumber,
        'dailyWage': dailyWage,
        'workerType': workerType ?? '',
        'notes': notes ?? '',
      },
    );
  }

  Future<MutationResult> archiveWorker({
    required String workspaceId,
    required String workerId,
  }) {
    return _enqueueForBackgroundSync(
      type: OfflineActionTypes.archiveWorker,
      payload: {
        'workspaceId': workspaceId,
        'workerId': workerId,
      },
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

  Future<String> ensureUserWorkspaceBootstrap() {
    return _client.call<String>(
      functionName: 'ensureUserWorkspaceBootstrap',
      payload: const {},
      parseResult: (result) {
        final data = Map<String, dynamic>.from(result as Map);
        return '${data['workspaceId'] ?? ''}';
      },
      defaultErrorMessage: 'Failed to set up your workspace.',
    );
  }

  Future<void> processQueuedAction(OfflineAction action) async {
    await _telemetry.log('offline_sync.process', {
      'type': action.type,
      'retry_count': action.retryCount,
    });
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
      case OfflineActionTypes.updateProject:
        await _client.call<void>(
          functionName: 'updateProject',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update project.',
        );
        return;
      case OfflineActionTypes.archiveProject:
        await _client.call<void>(
          functionName: 'archiveProject',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive project.',
        );
        return;
      case OfflineActionTypes.deleteProject:
        await _client.call<void>(
          functionName: 'deleteProjectCascade',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to delete project.',
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
      case OfflineActionTypes.updateExpense:
        await _client.call<void>(
          functionName: 'updateExpense',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update expense.',
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
      case OfflineActionTypes.updatePayment:
        await _client.call<void>(
          functionName: 'updatePayment',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update payment.',
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
      case OfflineActionTypes.createWorker:
        await _client.call<Map<String, dynamic>>(
          functionName: 'createWorker',
          payload: action.payload,
          parseResult: (result) => Map<String, dynamic>.from(result as Map),
          defaultErrorMessage: 'Failed to save worker.',
        );
        return;
      case OfflineActionTypes.updateWorker:
        await _client.call<void>(
          functionName: 'updateWorker',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update worker.',
        );
        return;
      case OfflineActionTypes.archiveWorker:
        await _client.call<void>(
          functionName: 'archiveWorker',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to archive worker.',
        );
        return;
      case OfflineActionTypes.updateWorkerEntry:
        await _client.call<void>(
          functionName: 'updateWorkerEntry',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update worker entry.',
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
      case OfflineActionTypes.updateUserProfile:
        await _client.call<void>(
          functionName: 'updateUserProfile',
          payload: action.payload,
          parseResult: (_) {},
          defaultErrorMessage: 'Failed to update profile.',
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
    final action = await _queue.enqueue(type: type, payload: payload);
    await _telemetry.log('offline_sync.enqueued', {'type': type});
    unawaited(_tryDrainInBackground());
    return MutationResult(id: action.id, queued: true);
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
    ref.watch(appTelemetryProvider),
  );
});
