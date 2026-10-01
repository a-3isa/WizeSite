import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/json_safe.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/features/transport/domain/transport_provider_accounting_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

/// Transport provider records (spec 004): read from the local PowerSync replica (the
/// financial sync bucket), saved through the offline queue to
/// `upsertTransportProviderAccountingRecord`.
class TransportProviderAccountingRepository {
  TransportProviderAccountingRepository(this._db, this._mutations);

  final Future<PowerSyncDatabase> _db;
  final WorkspaceMutationService _mutations;

  Future<void> save(TransportProviderAccountingRecord record) async {
    await _mutations.upsertAccountingRecord(
      kind: 'transport',
      record: {...jsonSafeMap(record.toMap()), 'id': record.id},
    );
  }

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
        TransportProviderAccountingRecord.fromMap('${row['id']}', localRowToMap('transport_provider_accounting_records', row)),
    ];
  }
}

final transportProviderAccountingRepositoryProvider = Provider<TransportProviderAccountingRepository>(
  (ref) => TransportProviderAccountingRepository(
    ref.watch(localDatabaseProvider),
    ref.watch(workspaceMutationServiceProvider),
  ),
);
