import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkerAccountingRepository {
  const WorkerAccountingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('worker_accounting_records');

  Future<void> save(WorkerAccountingRecord record) {
    return _collection.doc(record.id).set({
      ...record.toMap(),
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
