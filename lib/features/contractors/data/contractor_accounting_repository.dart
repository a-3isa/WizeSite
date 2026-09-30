import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/contractors/domain/contractor_accounting_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

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

/// Reads from the local PowerSync replica (spec 004, tasks.md T047). This
/// table is in the financial sync bucket. [save] stays the inherited direct
/// write until US2 moves it behind an RPC.
class LocalContractorAccountingRepository
    extends ContractorAccountingRepository {
  LocalContractorAccountingRepository(super.firestore, this._db);

  final Future<PowerSyncDatabase> _db;

  @override
  Future<List<ContractorAccountingRecord>> fetchForContractor({
    required String workspaceId,
    required String contractorId,
    int limit = 50,
  }) async {
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM contractor_accounting_records WHERE workspace_id = ? AND contractor_id = ? '
      'ORDER BY date DESC, id DESC LIMIT ?',
      [workspaceId, contractorId, limit],
    );
    return [
      for (final row in rows)
        ContractorAccountingRecord.fromMap(
          '${row['id']}',
          localRowToMap('contractor_accounting_records', row),
        ),
    ];
  }
}

final contractorAccountingRepositoryProvider =
    Provider<ContractorAccountingRepository>(
      (ref) => BackendConfig.fromEnvironment.useSelfHostedBackend
          ? LocalContractorAccountingRepository(
              ref.watch(firestoreProvider),
              ref.watch(localDatabaseProvider),
            )
          : ContractorAccountingRepository(ref.watch(firestoreProvider)),
    );
