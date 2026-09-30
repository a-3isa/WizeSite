import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_record_draft.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DomainAccountingSaveAdapter {
  const DomainAccountingSaveAdapter(this._firestore);

  final FirebaseFirestore _firestore;

  Future<void> save({
    required String collectionName,
    required DomainAccountingRecordDraft draft,
  }) {
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
      (ref) => DomainAccountingSaveAdapter(ref.watch(firestoreProvider)),
    );
