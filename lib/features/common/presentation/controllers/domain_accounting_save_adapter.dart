import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_record_draft.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class DomainAccountingSaveAdapter {
  const DomainAccountingSaveAdapter(this._firestore, {this.mutations});

  final FirebaseFirestore _firestore;

  /// Self-hosted builds (spec 004, T082): the record is queued for the
  /// matching upsert RPC instead of written to Firestore.
  final WorkspaceMutationService? mutations;

  Future<void> save({
    required String collectionName,
    required DomainAccountingRecordDraft draft,
  }) async {
    final queue = mutations;
    final kind = accountingRecordKinds[collectionName];
    if (queue != null && kind != null) {
      await queue.upsertAccountingRecord(
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
          // Worker partial payments need it (the Firestore write dropped it).
          'paidAmount': ?draft.paidAmount,
          'notes': draft.notes,
          'attachments': const <Map<String, dynamic>>[],
        },
      );
      return;
    }
    final doc = _firestore.collection(collectionName).doc();
    return doc.set({
      'workspaceId': draft.workspaceId,
      'projectId': draft.projectId,
      draft.ownerIdField: draft.ownerId,
      draft.ownerNameField: draft.ownerName,
      'description': draft.description,
      'amount': draft.amount,
      'date': Timestamp.fromDate(draft.date),
      'paymentMethod': draft.paymentMethod,
      'paymentStatus': draft.paymentStatus,
      'notes': draft.notes,
      'attachments': const <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

final domainAccountingSaveAdapterProvider =
    Provider<DomainAccountingSaveAdapter>(
      (ref) => DomainAccountingSaveAdapter(
        ref.watch(firestoreProvider),
        mutations: BackendConfig.fromEnvironment.useSelfHostedBackend
            ? ref.watch(workspaceMutationServiceProvider)
            : null,
      ),
    );
