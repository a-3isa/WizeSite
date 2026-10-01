import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/json_safe.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

/// Worker accounting records (spec 004): read from the local PowerSync replica
/// (the financial sync bucket), saved through the offline queue to
/// `upsertWorkerAccountingRecord`, which also recomputes the worker summary.
class WorkerAccountingRepository {
  WorkerAccountingRepository(this._db, this._mutations);

  final Future<PowerSyncDatabase> _db;
  final WorkspaceMutationService _mutations;

  static String summaryDocId(String workspaceId, String workerId) =>
      '${workspaceId}_$workerId';

  /// The maintained, exact summary for a worker; null until one is computed.
  /// Totals are independent of the [fetchForWorker] page cap.
  Future<WorkerAccountingSummary?> fetchSummary({
    required String workspaceId,
    required String workerId,
  }) async {
    final id = summaryDocId(workspaceId, workerId);
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM worker_accounting_summaries WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    return WorkerAccountingSummary.fromMap(
      id,
      localRowToMap('worker_accounting_summaries', rows.first),
    );
  }

  Future<void> save(WorkerAccountingRecord record) async {
    await _mutations.upsertAccountingRecord(
      kind: 'worker',
      record: {
        ...jsonSafeMap(record.toMap()),
        'id': record.id.isEmpty ? const Uuid().v4() : record.id,
      },
    );
  }

  Future<List<WorkerAccountingRecord>> fetchForWorker({
    required String workspaceId,
    required String workerId,
    int limit = 50,
  }) async {
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM worker_accounting_records '
      'WHERE workspace_id = ? AND worker_id = ? '
      'ORDER BY date DESC, id DESC LIMIT ?',
      [workspaceId, workerId, limit],
    );
    return [
      for (final row in rows)
        WorkerAccountingRecord.fromMap(
          '${row['id']}',
          localRowToMap('worker_accounting_records', row),
        ),
    ];
  }
}

final workerAccountingRepositoryProvider = Provider<WorkerAccountingRepository>(
  (ref) => WorkerAccountingRepository(
    ref.watch(localDatabaseProvider),
    ref.watch(workspaceMutationServiceProvider),
  ),
);
