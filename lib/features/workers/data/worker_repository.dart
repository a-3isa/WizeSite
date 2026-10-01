import 'package:buildtrack_app/core/pagination/local_page.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

abstract interface class WorkerRepository {
  /// Watches non-archived workers. When [statuses] is provided, only workers
  /// whose [WorkerProfile.status] is in the set are emitted. Status filtering
  /// is independent of the archived flag (archived workers are always excluded).
  Stream<List<WorkerProfile>> watchWorkers(
    String workspaceId, {
    Set<WorkerStatus>? statuses,
  });
  Future<RecordPage<WorkerProfile>> fetchWorkersPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
    Set<WorkerStatus>? statuses,
  });
  Future<WorkerProfile?> getWorker(String workerId);
  Future<void> createWorker({
    required String workspaceId,
    required String userId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    WorkerStatus status = WorkerStatus.active,
  });

  Future<void> updateWorker({
    required String workerId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    WorkerStatus? status,
  });

  Future<void> archiveWorker(String workerId);
}

abstract interface class WorkerEntryRepository {
  Stream<List<WorkerEntryRecord>> watchEntriesByWorker({
    required String workspaceId,
    required String workerId,
  });

  Future<WorkerEntryRecord?> getEntry(String entryId);

  Future<MutationResult> createEntry({
    required String workspaceId,
    required String userId,
    required String workerId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
    List<Attachment>? attachments,
    double? projectTotalExpensesBefore,
  });

  Future<void> updateEntry({
    required String entryId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
    List<Attachment>? attachments,
  });

  Future<MutationResult> archiveEntry(String entryId);
}

/// Workers read from the local PowerSync replica (spec 004, T045); pending
/// queue actions are overlaid on the rows. Writes are queued RPCs.
class LocalWorkerRepository implements WorkerRepository {
  LocalWorkerRepository(this._mutationService, this._queue, this._db);

  final WorkspaceMutationService _mutationService;
  final OfflineActionQueue _queue;
  final Future<PowerSyncDatabase> _db;

  WorkerProfile _fromRow(LocalRow row) =>
      WorkerProfile.fromMap('${row['id']}', localRowToMap('workers', row));

  @override
  Stream<List<WorkerProfile>> watchWorkers(
    String workspaceId, {
    Set<WorkerStatus>? statuses,
  }) {
    // Firestore applied limit(50) without an orderBy, which Firestore serves
    // in document-id order; the replica does the same so the list users see
    // does not reorder at cutover (read parity, T033).
    return combineWithQueue(
      rows: watchLocalRows(
        _db,
        'SELECT * FROM workers WHERE workspace_id = ? AND is_archived = 0 '
        'ORDER BY id ASC LIMIT 50',
        [workspaceId],
      ),
      queue: _queue,
      combine: (rows, actions) {
        final workers = _applyPendingWorkers(
          [for (final row in rows) _fromRow(row)],
          actions,
          workspaceId,
        );
        return statuses == null
            ? workers
            : workers
                  .where((worker) => statuses.contains(worker.status))
                  .toList(growable: false);
      },
    );
  }

  @override
  Future<RecordPage<WorkerProfile>> fetchWorkersPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
    Set<WorkerStatus>? statuses,
  }) async {
    final keyset = cursor as LocalPageCursor?;
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM workers WHERE workspace_id = ? AND is_archived = 0'
      '${keyset == null ? '' : ' AND (created_at < ? OR (created_at = ? AND id < ?))'} '
      'ORDER BY created_at DESC, id DESC LIMIT ?',
      [
        workspaceId,
        if (keyset != null) ...[keyset.sortValue, keyset.sortValue, keyset.id],
        pageSize,
      ],
    );
    final items = [
      for (final row in rows) _fromRow(row),
    ].where((w) => statuses == null || statuses.contains(w.status)).toList();
    final last = rows.isEmpty ? null : rows.last;
    return RecordPage<WorkerProfile>(
      items: items,
      hasMore: rows.length == pageSize,
      nextCursor: last == null
          ? cursor
          : LocalPageCursor(sortValue: last['created_at'], id: '${last['id']}'),
    );
  }

  @override
  Future<WorkerProfile?> getWorker(String workerId) async {
    final rows = await getLocalRows(_db, 'SELECT * FROM workers WHERE id = ?', [
      workerId,
    ]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<void> createWorker({
    required String workspaceId,
    required String userId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    WorkerStatus status = WorkerStatus.active,
  }) async {
    await _mutationService.createWorker(
      workspaceId: workspaceId,
      name: name,
      phoneNumber: phoneNumber,
      dailyWage: dailyWage,
      billingType: billingType,
      workerType: workerType,
      notes: notes,
      status: status.value,
    );
  }

  @override
  Future<void> updateWorker({
    required String workerId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    WorkerStatus? status,
  }) async {
    final worker = await getWorker(workerId);
    if (worker == null) {
      return;
    }
    await _mutationService.updateWorker(
      workspaceId: worker.workspaceId,
      workerId: workerId,
      name: name,
      phoneNumber: phoneNumber,
      dailyWage: dailyWage,
      billingType: billingType,
      workerType: workerType,
      notes: notes,
      status: (status ?? worker.status).value,
    );
  }

  @override
  Future<void> archiveWorker(String workerId) async {
    final worker = await getWorker(workerId);
    if (worker == null) {
      return;
    }
    await _mutationService.archiveWorker(
      workspaceId: worker.workspaceId,
      workerId: workerId,
    );
  }

  List<WorkerProfile> _applyPendingWorkers(
    List<WorkerProfile> baseItems,
    List<OfflineAction> actions,
    String workspaceId,
  ) {
    final items = List<WorkerProfile>.from(baseItems);
    final archivedIds = <String>{};

    for (final action in actions) {
      if ('${action.payload['workspaceId'] ?? ''}' != workspaceId) {
        continue;
      }
      if (action.type == OfflineActionTypes.archiveWorker) {
        final workerId = '${action.payload['workerId'] ?? ''}';
        if (workerId.isNotEmpty) {
          archivedIds.add(workerId);
        }
      }
    }
    items.removeWhere((item) => archivedIds.contains(item.id));

    for (final action in actions) {
      if (action.type != OfflineActionTypes.updateWorker ||
          '${action.payload['workspaceId'] ?? ''}' != workspaceId) {
        continue;
      }
      final workerId = '${action.payload['workerId'] ?? ''}';
      final index = items.indexWhere((item) => item.id == workerId);
      if (index < 0) {
        continue;
      }
      final current = items[index];
      items[index] = WorkerProfile(
        id: current.id,
        workspaceId: current.workspaceId,
        name: '${action.payload['name'] ?? current.name}',
        phoneNumber: '${action.payload['phoneNumber'] ?? current.phoneNumber}',
        dailyWage:
            (action.payload['dailyWage'] as num?)?.toDouble() ??
            current.dailyWage,
        billingType: '${action.payload['billingType'] ?? current.billingType}',
        workerType: '${action.payload['workerType'] ?? current.workerType}',
        notes: '${action.payload['notes'] ?? current.notes}',
        isArchived: current.isArchived,
        status: WorkerStatus.fromValue(
          action.payload['status'] as String? ?? current.status.value,
        ),
        clientMutationId: current.clientMutationId,
      );
    }

    final liveMutationIds = items
        .map((item) => item.clientMutationId)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final action in actions) {
      if (action.type != OfflineActionTypes.createWorker ||
          '${action.payload['workspaceId'] ?? ''}' != workspaceId) {
        continue;
      }
      final clientMutationId = '${action.payload['clientMutationId'] ?? ''}';
      if (clientMutationId.isNotEmpty &&
          liveMutationIds.contains(clientMutationId)) {
        continue;
      }
      items.insert(0, _workerFromCreateAction(action));
    }

    final deduped = <String, WorkerProfile>{};
    for (final item in items) {
      deduped[item.id] = item;
    }
    return deduped.values.toList(growable: false);
  }

  WorkerProfile _workerFromCreateAction(OfflineAction action) {
    final payload = action.payload;
    return WorkerProfile(
      id: 'pending_${action.id}',
      workspaceId: '${payload['workspaceId'] ?? ''}',
      name: '${payload['name'] ?? ''}',
      phoneNumber: '${payload['phoneNumber'] ?? ''}',
      dailyWage: (payload['dailyWage'] as num?)?.toDouble() ?? 0,
      billingType: '${payload['billingType'] ?? 'daily'}',
      workerType: '${payload['workerType'] ?? ''}',
      notes: '${payload['notes'] ?? ''}',
      isArchived: false,
      status: WorkerStatus.fromValue(payload['status'] as String?),
      clientMutationId: '${payload['clientMutationId'] ?? action.id}',
    );
  }
}

/// Worker entries read from the local PowerSync replica (spec 004, T045);
/// pending queue actions are overlaid on the rows. Writes are queued RPCs.
class LocalWorkerEntryRepository implements WorkerEntryRepository {
  LocalWorkerEntryRepository(this._mutationService, this._queue, this._db);

  final WorkspaceMutationService _mutationService;
  final OfflineActionQueue _queue;
  final Future<PowerSyncDatabase> _db;

  WorkerEntryRecord _fromRow(LocalRow row) => WorkerEntryRecord.fromMap(
    '${row['id']}',
    localRowToMap('worker_entries', row),
  );

  @override
  Stream<List<WorkerEntryRecord>> watchEntriesByWorker({
    required String workspaceId,
    required String workerId,
  }) {
    return combineWithQueue(
      rows: watchLocalRows(
        _db,
        'SELECT * FROM worker_entries WHERE workspace_id = ? AND worker_id = ? '
        'AND is_archived = 0 ORDER BY date DESC, id DESC',
        [workspaceId, workerId],
      ),
      queue: _queue,
      combine: (rows, actions) => _applyPendingEntries(
        baseItems: [for (final row in rows) _fromRow(row)],
        actions: actions,
        workspaceId: workspaceId,
        workerId: workerId,
      ),
    );
  }

  @override
  Future<WorkerEntryRecord?> getEntry(String entryId) async {
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM worker_entries WHERE id = ?',
      [entryId],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<MutationResult> createEntry({
    required String workspaceId,
    required String userId,
    required String workerId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
    List<Attachment>? attachments,
    double? projectTotalExpensesBefore,
  }) async {
    return _mutationService.createWorkerEntry(
      workspaceId: workspaceId,
      workerId: workerId,
      projectId: projectId,
      daysWorked: daysWorked,
      dailyWage: dailyWage,
      date: date,
      notes: notes,
      attachments: attachments
          ?.map((attachment) => attachment.toMap())
          .toList(growable: false),
      projectTotalExpensesBefore: projectTotalExpensesBefore,
    );
  }

  @override
  Future<void> updateEntry({
    required String entryId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
    List<Attachment>? attachments,
  }) async {
    final entry = await getEntry(entryId);
    if (entry == null) {
      return;
    }
    await _mutationService.updateWorkerEntry(
      workspaceId: entry.workspaceId,
      entryId: entryId,
      projectId: projectId,
      daysWorked: daysWorked,
      dailyWage: dailyWage,
      date: date,
      notes: notes,
      attachments: (attachments ?? entry.attachments)
          .map((attachment) => attachment.toMap())
          .toList(growable: false),
      previousProjectId: entry.projectId,
      previousDaysWorked: entry.daysWorked,
      previousDailyWage: entry.dailyWage,
      previousTotalCost: entry.totalCost,
      previousDate: entry.date,
    );
  }

  @override
  Future<MutationResult> archiveEntry(String entryId) async {
    final entry = await getEntry(entryId);
    if (entry == null) {
      return const MutationResult();
    }
    return _mutationService.archiveWorkerEntry(
      workspaceId: entry.workspaceId,
      entryId: entryId,
      projectId: entry.projectId,
      daysWorked: entry.daysWorked,
      dailyWage: entry.dailyWage,
      totalCost: entry.totalCost,
      date: entry.date,
    );
  }

  List<WorkerEntryRecord> _applyPendingEntries({
    required List<WorkerEntryRecord> baseItems,
    required List<OfflineAction> actions,
    required String workspaceId,
    required String workerId,
  }) {
    final items = List<WorkerEntryRecord>.from(baseItems);
    final archivedIds = <String>{};

    for (final action in actions) {
      final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
      if (payloadWorkspaceId != workspaceId) {
        continue;
      }
      if (action.type == OfflineActionTypes.archiveWorkerEntry) {
        final entryId = '${action.payload['entryId'] ?? ''}';
        if (entryId.isNotEmpty) {
          archivedIds.add(entryId);
        }
      }
    }

    if (archivedIds.isNotEmpty) {
      items.removeWhere((item) => archivedIds.contains(item.id));
    }

    for (final action in actions) {
      if (action.type != OfflineActionTypes.updateWorkerEntry ||
          '${action.payload['workspaceId'] ?? ''}' != workspaceId) {
        continue;
      }
      final entryId = '${action.payload['entryId'] ?? ''}';
      final index = items.indexWhere((item) => item.id == entryId);
      if (index < 0) {
        continue;
      }
      final current = items[index];
      final daysWorked =
          (action.payload['daysWorked'] as num?)?.toDouble() ??
          current.daysWorked;
      final dailyWage =
          (action.payload['dailyWage'] as num?)?.toDouble() ??
          current.dailyWage;
      items[index] = WorkerEntryRecord(
        id: current.id,
        workspaceId: current.workspaceId,
        workerId: current.workerId,
        projectId: '${action.payload['projectId'] ?? current.projectId}',
        daysWorked: daysWorked,
        dailyWage: dailyWage,
        totalCost: daysWorked * dailyWage,
        date:
            DateTime.tryParse('${action.payload['date'] ?? ''}') ??
            current.date,
        notes: '${action.payload['notes'] ?? current.notes}',
        isArchived: current.isArchived,
        attachments: action.payload.containsKey('attachments')
            ? Attachment.listFromDynamic(action.payload['attachments'])
            : current.attachments,
        clientMutationId: current.clientMutationId,
      );
    }

    for (final action in actions) {
      if (action.type != OfflineActionTypes.createWorkerEntry) {
        continue;
      }
      final liveMutationIds = items
          .map((item) => item.clientMutationId)
          .where((id) => id.isNotEmpty)
          .toSet();
      final clientMutationId = '${action.payload['clientMutationId'] ?? ''}';
      if (clientMutationId.isNotEmpty &&
          liveMutationIds.contains(clientMutationId)) {
        continue;
      }
      final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
      final payloadWorkerId = '${action.payload['workerId'] ?? ''}';
      if (payloadWorkspaceId != workspaceId || payloadWorkerId != workerId) {
        continue;
      }
      items.insert(0, _entryFromCreateAction(action));
    }

    final deduped = <String, WorkerEntryRecord>{};
    for (final item in items) {
      deduped[item.id] = item;
    }
    final result = deduped.values.toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  WorkerEntryRecord _entryFromCreateAction(OfflineAction action) {
    final payload = action.payload;
    final parsedDate = DateTime.tryParse('${payload['date'] ?? ''}');
    final daysWorked = (payload['daysWorked'] as num?)?.toDouble() ?? 0;
    final dailyWage = (payload['dailyWage'] as num?)?.toDouble() ?? 0;
    return WorkerEntryRecord(
      id: 'pending_${action.id}',
      workspaceId: '${payload['workspaceId'] ?? ''}',
      workerId: '${payload['workerId'] ?? ''}',
      projectId: '${payload['projectId'] ?? ''}',
      daysWorked: daysWorked,
      dailyWage: dailyWage,
      totalCost: daysWorked * dailyWage,
      date: parsedDate ?? action.createdAt,
      notes: '${payload['notes'] ?? ''}',
      isArchived: false,
      attachments: Attachment.listFromDynamic(payload['attachments']),
      clientMutationId: '${payload['clientMutationId'] ?? action.id}',
    );
  }
}

final workerRepositoryProvider = Provider<WorkerRepository>((ref) {
  return LocalWorkerRepository(
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
    ref.watch(localDatabaseProvider),
  );
});

final workerEntryRepositoryProvider = Provider<WorkerEntryRepository>((ref) {
  return LocalWorkerEntryRepository(
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
    ref.watch(localDatabaseProvider),
  );
});
