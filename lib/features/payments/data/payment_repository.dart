import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class PaymentRepository {
  Stream<List<PaymentRecord>> watchPayments(String workspaceId);
  Future<PaymentRecord?> getPayment(String paymentId);
  Future<void> createPayment({
    required String workspaceId,
    required String userId,
    required String projectId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? notes,
  });

  Future<void> updatePayment({
    required String paymentId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? notes,
  });

  Future<void> archivePayment(String paymentId);
}

class FirebasePaymentRepository implements PaymentRepository {
  FirebasePaymentRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<PaymentRecord>> watchPayments(String workspaceId) {
    return _firestore
        .collection('payments')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => PaymentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<PaymentRecord?> getPayment(String paymentId) async {
    final snap = await _firestore.collection('payments').doc(paymentId).get();
    if (!snap.exists) {
      return null;
    }
    return PaymentRecord.fromMap(snap.id, snap.data() ?? const {});
  }

  @override
  Future<void> createPayment({
    required String workspaceId,
    required String userId,
    required String projectId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? notes,
  }) async {
    final ref = _firestore.collection('payments').doc();
    await ref.set({
      'id': ref.id,
      'workspaceId': workspaceId,
      'projectId': projectId,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'paymentMethod': paymentMethod,
      'notes': notes ?? '',
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isArchived': false,
    });
  }

  @override
  Future<void> updatePayment({
    required String paymentId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? notes,
  }) async {
    await _firestore.collection('payments').doc(paymentId).update({
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'paymentMethod': paymentMethod,
      'notes': notes ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> archivePayment(String paymentId) async {
    await _firestore.collection('payments').doc(paymentId).update({
      'isArchived': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return FirebasePaymentRepository(ref.watch(firestoreProvider));
});
