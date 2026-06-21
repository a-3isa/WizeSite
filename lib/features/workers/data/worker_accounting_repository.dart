import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final workerAccountingRepositoryProvider = Provider<WorkerAccountingRepository>(
  (ref) => WorkerAccountingRepository(ref.watch(firestoreProvider)),
);
