import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ExpenseRepository {
  Stream<List<Expense>> watchExpenses(String workspaceId);
  Future<Expense?> getExpense(String expenseId);
  Future<void> createExpense({
    required String workspaceId,
    required String userId,
    required String projectId,
    String? projectName,
    required String category,
    required double amount,
    String? currency,
    required DateTime date,
    String? notes,
    String? supplierName,
    String? paymentMethod,
  });

  Future<void> updateExpense({
    required String expenseId,
    required String category,
    required double amount,
    required DateTime date,
    String? notes,
    String? supplierName,
    String? paymentMethod,
  });

  Future<void> archiveExpense(String expenseId);
}

class FirebaseExpenseRepository implements ExpenseRepository {
  FirebaseExpenseRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<Expense>> watchExpenses(String workspaceId) {
    return _firestore
        .collection('expenses')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Expense.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<Expense?> getExpense(String expenseId) async {
    final snap = await _firestore.collection('expenses').doc(expenseId).get();
    if (!snap.exists) {
      return null;
    }
    return Expense.fromMap(snap.id, snap.data() ?? const {});
  }

  @override
  Future<void> createExpense({
    required String workspaceId,
    required String userId,
    required String projectId,
    String? projectName,
    required String category,
    required double amount,
    String? currency,
    required DateTime date,
    String? notes,
    String? supplierName,
    String? paymentMethod,
  }) async {
    final ref = _firestore.collection('expenses').doc();
    await ref.set({
      'id': ref.id,
      'workspaceId': workspaceId,
      'projectId': projectId,
      'projectName': projectName ?? '',
      'category': category,
      'amount': amount,
      'currency': currency ?? 'EGP',
      'date': Timestamp.fromDate(date),
      'notes': notes ?? '',
      'supplierName': supplierName ?? '',
      'paymentMethod': paymentMethod ?? '',
      'inputMethod': 'manual',
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isArchived': false,
    });
  }

  @override
  Future<void> updateExpense({
    required String expenseId,
    required String category,
    required double amount,
    required DateTime date,
    String? notes,
    String? supplierName,
    String? paymentMethod,
  }) async {
    await _firestore.collection('expenses').doc(expenseId).update({
      'category': category,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'notes': notes ?? '',
      'supplierName': supplierName ?? '',
      'paymentMethod': paymentMethod ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> archiveExpense(String expenseId) async {
    await _firestore.collection('expenses').doc(expenseId).update({
      'isArchived': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return FirebaseExpenseRepository(ref.watch(firestoreProvider));
});
