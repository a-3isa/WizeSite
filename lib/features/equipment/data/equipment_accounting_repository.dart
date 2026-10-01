import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/json_safe.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/features/equipment/domain/equipment_accounting_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

/// Equipment provider records (spec 004): read from the local PowerSync replica (the
/// financial sync bucket), saved through the offline queue to
/// `upsertEquipmentAccountingRecord`.
class EquipmentAccountingRepository {
  EquipmentAccountingRepository(this._db, this._mutations);

  final Future<PowerSyncDatabase> _db;
  final WorkspaceMutationService _mutations;

  Future<void> save(EquipmentAccountingRecord record) async {
    await _mutations.upsertAccountingRecord(
      kind: 'equipment',
      record: {...jsonSafeMap(record.toMap()), 'id': record.id},
    );
  }

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
        EquipmentAccountingRecord.fromMap('${row['id']}', localRowToMap('equipment_accounting_records', row)),
    ];
  }
}

final equipmentAccountingRepositoryProvider = Provider<EquipmentAccountingRepository>(
  (ref) => EquipmentAccountingRepository(
    ref.watch(localDatabaseProvider),
    ref.watch(workspaceMutationServiceProvider),
  ),
);
