part of 'worker_repository.dart';

/// Worker reads from the local PowerSync replica (spec 004, tasks.md T045).
/// Overlay semantics are the inherited private helpers; writes are inherited.
class LocalWorkerRepository extends FirebaseWorkerRepository {
  LocalWorkerRepository(
    super.firestore,
    super.mutationService,
    super.queue,
    this._db,
  );

  final Future<PowerSyncDatabase> _db;

  WorkerProfile _fromRow(LocalRow row) =>
      WorkerProfile.fromMap('${row['id']}', localRowToMap('workers', row));

  @override
  Stream<List<WorkerProfile>> watchWorkers(
    String workspaceId, {
    Set<WorkerStatus>? statuses,
  }) {
    // Firestore applied limit(50) without an order, i.e. an arbitrary 50; the
    // replica orders newest first so the same 50 come back every time.
    return combineWithQueue(
      rows: watchLocalRows(
        _db,
        'SELECT * FROM workers WHERE workspace_id = ? AND is_archived = 0 '
        'ORDER BY created_at DESC, id DESC LIMIT 50',
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
  Future<FirestorePage<WorkerProfile>> fetchWorkersPage(
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
    return FirestorePage<WorkerProfile>(
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
}

/// Worker-entry reads from the local PowerSync replica (tasks.md T045).
class LocalWorkerEntryRepository extends FirebaseWorkerEntryRepository {
  LocalWorkerEntryRepository(
    super.firestore,
    super.mutationService,
    super.queue,
    this._db,
  );

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
}
