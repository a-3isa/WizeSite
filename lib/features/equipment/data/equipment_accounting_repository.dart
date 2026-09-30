import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/equipment/domain/equipment_accounting_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

class EquipmentAccountingRepository {
  const EquipmentAccountingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('equipment_accounting_records');

  Future<void> save(EquipmentAccountingRecord record) {
    return _collection.doc(record.id).set({
      ...record.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<EquipmentAccountingRecord>> fetchForProvider({
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
        .map((doc) => EquipmentAccountingRecord.fromMap(doc.id, doc.data()))
        .toList(growable: false);
  }
}

/// Reads from the local PowerSync replica (spec 004, tasks.md T047). This
/// table is in the financial sync bucket. [save] stays the inherited direct
/// write until US2 moves it behind an RPC.
class LocalEquipmentAccountingRepository extends EquipmentAccountingRepository {
  LocalEquipmentAccountingRepository(super.firestore, this._db);

  final Future<PowerSyncDatabase> _db;

  @override
  Future<List<EquipmentAccountingRecord>> fetchForProvider({
    required String workspaceId,
    required String providerId,
    int limit = 50,
  }) async {
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM equipment_accounting_records WHERE workspace_id = ? AND provider_id = ? '
      'ORDER BY date DESC, id DESC LIMIT ?',
      [workspaceId, providerId, limit],
    );
    return [
      for (final row in rows)
        EquipmentAccountingRecord.fromMap(
          '${row['id']}',
          localRowToMap('equipment_accounting_records', row),
        ),
    ];
  }
}

final equipmentAccountingRepositoryProvider =
    Provider<EquipmentAccountingRepository>(
      (ref) => BackendConfig.fromEnvironment.useSelfHostedBackend
          ? LocalEquipmentAccountingRepository(
              ref.watch(firestoreProvider),
              ref.watch(localDatabaseProvider),
            )
          : EquipmentAccountingRepository(ref.watch(firestoreProvider)),
    );
