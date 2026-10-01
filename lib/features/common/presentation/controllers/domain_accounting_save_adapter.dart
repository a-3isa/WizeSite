import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_record_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Saves a domain accounting record (worker, contractor, equipment, transport)
/// through the offline queue to the family's upsert RPC (spec 004, T082).
class DomainAccountingSaveAdapter {
  const DomainAccountingSaveAdapter(this._mutations);

  final WorkspaceMutationService _mutations;

  Future<void> save({
    required String collectionName,
    required DomainAccountingRecordDraft draft,
  }) async {
    final kind = accountingRecordKinds[collectionName];
    if (kind == null) {
      throw ArgumentError.value(
        collectionName,
        'collectionName',
        'Not an accounting record collection',
      );
    }
    await _mutations.upsertAccountingRecord(
      kind: kind,
      record: {
        'id': const Uuid().v4(),
        'workspaceId': draft.workspaceId,
        'projectId': draft.projectId,
        draft.ownerIdField: draft.ownerId,
        draft.ownerNameField: draft.ownerName,
        'description': draft.description,
        'amount': draft.amount,
        'date': draft.date.toUtc().toIso8601String(),
        'paymentMethod': draft.paymentMethod,
        'paymentStatus': draft.paymentStatus,
        // Worker partial payments need it.
        'paidAmount': ?draft.paidAmount,
        'notes': draft.notes,
        'attachments': const <Map<String, dynamic>>[],
      },
    );
  }
}

final domainAccountingSaveAdapterProvider =
    Provider<DomainAccountingSaveAdapter>(
      (ref) =>
          DomainAccountingSaveAdapter(ref.watch(workspaceMutationServiceProvider)),
    );
