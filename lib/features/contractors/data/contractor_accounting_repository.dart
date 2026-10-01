import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/json_safe.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/features/contractors/domain/contractor_accounting_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

/// Contractor accounting records (spec 004): read from the local PowerSync replica (the
/// financial sync bucket), saved through the offline queue to
/// `upsertContractorAccountingRecord`.
class ContractorAccountingRepository {
  ContractorAccountingRepository(this._db, this._mutations);

  final Future<PowerSyncDatabase> _db;
  final WorkspaceMutationService _mutations;

  Future<void> save(ContractorAccountingRecord record) async {
    await _mutations.upsertAccountingRecord(
      kind: 'contractor',
      record: {...jsonSafeMap(record.toMap()), 'id': record.id},
    );
  }

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
        ContractorAccountingRecord.fromMap('${row['id']}', localRowToMap('contractor_accounting_records', row)),
    ];
  }
}

final contractorAccountingRepositoryProvider = Provider<ContractorAccountingRepository>(
  (ref) => ContractorAccountingRepository(
    ref.watch(localDatabaseProvider),
    ref.watch(workspaceMutationServiceProvider),
  ),
);
