import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

class WorkerAccountingRepository {
  const WorkerAccountingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('worker_accounting_records');

  CollectionReference<Map<String, dynamic>> get _summaries =>
      _firestore.collection('worker_accounting_summaries');

  static String summaryDocId(String workspaceId, String workerId) =>
      '${workspaceId}_$workerId';

  /// Reads the maintained, exact summary for a worker. Returns null when no
  /// summary has been computed yet. Totals are independent of the
  /// [fetchForWorker] page cap.
  Future<WorkerAccountingSummary?> fetchSummary({
    required String workspaceId,
    required String workerId,
  }) async {
    final snap = await _summaries
        .doc(summaryDocId(workspaceId, workerId))
        .get();
    final data = snap.data();
    if (!snap.exists || data == null) {
      return null;
    }
    return WorkerAccountingSummary.fromMap(snap.id, data);
  }

  Future<void> save(WorkerAccountingRecord record) {
    final doc = record.id.isEmpty
        ? _collection.doc()
        : _collection.doc(record.id);
    return doc.set({
      ...record.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<WorkerAccountingRecord>> fetchForWorker({
    required String workspaceId,
    required String workerId,
    int limit = 50,
  }) async {
    final snap = await _collection
        .where('workspaceId', isEqualTo: workspaceId)
        .where('workerId', isEqualTo: workerId)
        .orderBy('date', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((doc) => WorkerAccountingRecord.fromMap(doc.id, doc.data()))
        .toList(growable: false);
  }
}

/// Reads from the local PowerSync replica (spec 004, tasks.md T045). These
/// tables are in the financial sync bucket, like `canAccessAccounting` in
/// firestore.rules. [save] is still the inherited direct write until US2 moves
/// it behind an RPC.
class LocalWorkerAccountingRepository extends WorkerAccountingRepository {
  LocalWorkerAccountingRepository(super.firestore, this._db);

  final Future<PowerSyncDatabase> _db;

  @override
  Future<WorkerAccountingSummary?> fetchSummary({
    required String workspaceId,
    required String workerId,
  }) async {
    final id = WorkerAccountingRepository.summaryDocId(workspaceId, workerId);
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

  @override
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
  (ref) => BackendConfig.fromEnvironment.useSelfHostedBackend
      ? LocalWorkerAccountingRepository(
          ref.watch(firestoreProvider),
          ref.watch(localDatabaseProvider),
        )
      : WorkerAccountingRepository(ref.watch(firestoreProvider)),
);
