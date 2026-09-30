import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

/// Which accounting records a domain screen lists: the 50 newest records of
/// one owner (contractor, equipment provider, transport provider, ...).
typedef DomainRecordsQuery = ({
  String collection,
  String ownerField,
  String ownerId,
  String workspaceId,
});

/// One record as its Firestore-shaped document (id + field map).
typedef DomainRecord = ({String id, Map<String, dynamic> data});

/// Collections and owner fields a domain screen may list. Checked before any
/// value is used as a SQL identifier.
const _allowedCollections = {
  'contractor_accounting_records',
  'equipment_accounting_records',
  'transport_provider_accounting_records',
  'worker_accounting_records',
};
const _allowedOwnerFields = {
  'contractorId',
  'providerId',
  'workerId',
  'equipmentId',
};

/// Local-replica variant of [domainAccountingRecordsProvider].
Stream<List<DomainRecord>> watchLocalDomainRecords(
  Future<PowerSyncDatabase> db,
  DomainRecordsQuery query,
) {
  if (!_allowedCollections.contains(query.collection) ||
      !_allowedOwnerFields.contains(query.ownerField)) {
    throw ArgumentError('Unsupported domain records query: $query');
  }
  return watchLocalRows(
    db,
    'SELECT * FROM ${query.collection} '
    'WHERE workspace_id = ? AND ${_snake(query.ownerField)} = ? '
    'ORDER BY date DESC, id DESC LIMIT 50',
    [query.workspaceId, query.ownerId],
  ).map(
    (rows) => [
      for (final row in rows)
        (id: '${row['id']}', data: localRowToMap(query.collection, row)),
    ],
  );
}

String _snake(String field) =>
    field.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

/// Live list for a domain accounting screen (spec 004, tasks.md T047): the
/// local replica in self-hosted builds, Firestore otherwise. Auto-disposed so
/// each screen gets its own subscription.
final domainAccountingRecordsProvider = Provider.autoDispose
    .family<Stream<List<DomainRecord>>, DomainRecordsQuery>((ref, query) {
      if (!_allowedCollections.contains(query.collection) ||
          !_allowedOwnerFields.contains(query.ownerField)) {
        throw ArgumentError('Unsupported domain records query: $query');
      }
      if (BackendConfig.fromEnvironment.useSelfHostedBackend) {
        return watchLocalDomainRecords(ref.watch(localDatabaseProvider), query);
      }
      return ref
          .watch(firestoreProvider)
          .collection(query.collection)
          .where('workspaceId', isEqualTo: query.workspaceId)
          .where(query.ownerField, isEqualTo: query.ownerId)
          .orderBy('date', descending: true)
          .limit(50)
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs) (id: doc.id, data: doc.data()),
            ],
          );
    });
