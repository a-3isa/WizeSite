import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/contractors/domain/contractor_accounting_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ContractorAccountingRepository {
  const ContractorAccountingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('contractor_accounting_records');

  Future<void> save(ContractorAccountingRecord record) {
    return _collection.doc(record.id).set({
      ...record.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<ContractorAccountingRecord>> fetchForContractor({
    required String workspaceId,
    required String contractorId,
    int limit = 50,
  }) async {
    final snap = await _collection
        .where('workspaceId', isEqualTo: workspaceId)
        .where('contractorId', isEqualTo: contractorId)
        .orderBy('date', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((doc) => ContractorAccountingRecord.fromMap(doc.id, doc.data()))
        .toList(growable: false);
  }
}

final contractorAccountingRepositoryProvider =
    Provider<ContractorAccountingRepository>(
      (ref) => ContractorAccountingRepository(ref.watch(firestoreProvider)),
    );
