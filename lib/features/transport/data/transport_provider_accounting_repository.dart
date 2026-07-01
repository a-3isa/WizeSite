import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/transport/domain/transport_provider_accounting_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TransportProviderAccountingRepository {
  const TransportProviderAccountingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('transport_provider_accounting_records');

  Future<void> save(TransportProviderAccountingRecord record) {
    return _collection.doc(record.id).set({
      ...record.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<TransportProviderAccountingRecord>> fetchForProvider({
    required String workspaceId,
    required String providerId,
    int limit = 50,
  }) async {
    final snap = await _collection
        .where('workspaceId', isEqualTo: workspaceId)
        .where('providerId', isEqualTo: providerId)
        .orderBy('date', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map(
          (doc) =>
              TransportProviderAccountingRecord.fromMap(doc.id, doc.data()),
        )
        .toList(growable: false);
  }
}

final transportProviderAccountingRepositoryProvider =
    Provider<TransportProviderAccountingRepository>(
      (ref) =>
          TransportProviderAccountingRepository(ref.watch(firestoreProvider)),
    );
