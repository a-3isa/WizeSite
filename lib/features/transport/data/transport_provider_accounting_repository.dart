import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/json_safe.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/transport/domain/transport_provider_accounting_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

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

/// Reads from the local PowerSync replica (spec 004, tasks.md T047). This
/// table is in the financial sync bucket. [save] stays the inherited direct
/// write until US2 moves it behind an RPC.
class LocalTransportProviderAccountingRepository
    extends TransportProviderAccountingRepository {
  LocalTransportProviderAccountingRepository(
    super.firestore,
    this._db, {
    WorkspaceMutationService? mutations,
  }) : _mutations = mutations;

  final Future<PowerSyncDatabase> _db;

  /// Writes go through the offline queue to the RPC API (spec 004, T082);
  /// without it (tests) [save] keeps the inherited Firestore write.
  final WorkspaceMutationService? _mutations;

  @override
  Future<void> save(TransportProviderAccountingRecord record) async {
    final mutations = _mutations;
    if (mutations == null) {
      return super.save(record);
    }
    await mutations.upsertAccountingRecord(
      kind: 'transport',
      record: {...jsonSafeMap(record.toMap()), 'id': record.id},
    );
  }

  @override
  Future<List<TransportProviderAccountingRecord>> fetchForProvider({
    required String workspaceId,
    required String providerId,
    int limit = 50,
  }) async {
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM transport_provider_accounting_records WHERE workspace_id = ? AND provider_id = ? '
      'ORDER BY date DESC, id DESC LIMIT ?',
      [workspaceId, providerId, limit],
    );
    return [
      for (final row in rows)
        TransportProviderAccountingRecord.fromMap(
          '${row['id']}',
          localRowToMap('transport_provider_accounting_records', row),
        ),
    ];
  }
}

final transportProviderAccountingRepositoryProvider =
    Provider<TransportProviderAccountingRepository>(
      (ref) => BackendConfig.fromEnvironment.useSelfHostedBackend
          ? LocalTransportProviderAccountingRepository(
              ref.watch(firestoreProvider),
              ref.watch(localDatabaseProvider),
              mutations: ref.watch(workspaceMutationServiceProvider),
            )
          : TransportProviderAccountingRepository(ref.watch(firestoreProvider)),
    );
