import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ExpenseRepository {
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId);
  Future<FirestorePage<Expense>> fetchExpensesPage(
    String workspaceId, {
    required String projectId,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  });
  Future<Expense?> getExpense(String expenseId);
  Future<MutationResult> createExpense({
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
    double? projectTotalExpensesBefore,
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

  Future<MutationResult> archiveExpense(String expenseId);
}

class FirebaseExpenseRepository implements ExpenseRepository {
  FirebaseExpenseRepository(
    this._firestore,
    this._mutationService,
    this._queue,
  );

  final FirebaseFirestore _firestore;
  final WorkspaceMutationService _mutationService;
  final OfflineActionQueue _queue;

  @override
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId) {
    final baseStream = _firestore
        .collection('expenses')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .where('isArchived', isEqualTo: false)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Expense.fromMap(doc.id, doc.data()))
              .toList(),
        );
    final queueStream = _queue.watch();
    return Stream.multi((controller) {
      List<Expense> current = const [];
      List<OfflineAction> actions = const [];

      void emit() {
        controller.add(
          _applyPendingExpenses(
            baseItems: current,
            actions: actions,
            workspaceId: workspaceId,
            projectId: projectId,
            includePendingCreates: true,
          ),
        );
      }

      final baseSub = baseStream.listen((items) {
        current = items;
        emit();
      }, onError: controller.addError);
      final queueSub = queueStream.listen((value) {
        actions = value;
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await baseSub.cancel();
        await queueSub.cancel();
      };
    });
  }

  @override
  Future<FirestorePage<Expense>> fetchExpensesPage(
    String workspaceId, {
    required String projectId,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    var query = _firestore
        .collection('expenses')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .where('isArchived', isEqualTo: false)
        .orderBy('date', descending: true)
        .limit(pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }

    final snap = await query.get();
    final items = snap.docs
        .map((doc) => Expense.fromMap(doc.id, doc.data()))
        .toList();
    final actions = await _queue.list();
    final mergedItems = _applyPendingExpenses(
      baseItems: items,
      actions: actions,
      workspaceId: workspaceId,
      projectId: projectId,
      includePendingCreates: cursor == null,
    );

    return FirestorePage<Expense>(
      items: mergedItems,
      hasMore: snap.docs.length == pageSize,
      nextCursor: snap.docs.isEmpty ? cursor : snap.docs.last,
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
  Future<MutationResult> createExpense({
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
    double? projectTotalExpensesBefore,
  }) async {
    return _mutationService.createManualExpense(
      workspaceId: workspaceId,
      projectId: projectId,
      projectName: projectName ?? '',
      category: category,
      amount: amount,
      currency: currency ?? 'EGP',
      date: date,
      notes: notes,
      supplierName: supplierName,
      paymentMethod: paymentMethod,
      projectTotalExpensesBefore: projectTotalExpensesBefore,
    );
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
    final expense = await getExpense(expenseId);
    if (expense == null) {
      return;
    }
    await _mutationService.updateExpense(
      workspaceId: expense.workspaceId,
      expenseId: expenseId,
      projectId: expense.projectId,
      category: category,
      amount: amount,
      date: date,
      notes: notes,
      supplierName: supplierName,
      paymentMethod: paymentMethod,
      previousAmount: expense.amount,
      previousDate: expense.date,
      previousCategory: expense.category,
    );
  }

  @override
  Future<MutationResult> archiveExpense(String expenseId) async {
    final expense = await getExpense(expenseId);
    if (expense == null) {
      return const MutationResult();
    }
    return _mutationService.archiveExpense(
      workspaceId: expense.workspaceId,
      expenseId: expenseId,
      projectId: expense.projectId,
      category: expense.category,
      amount: expense.amount,
      date: expense.date,
    );
  }

  List<Expense> _applyPendingExpenses({
    required List<Expense> baseItems,
    required List<OfflineAction> actions,
    required String workspaceId,
    required String projectId,
    required bool includePendingCreates,
  }) {
    final items = List<Expense>.from(baseItems);
    final archivedIds = <String>{};

    for (final action in actions) {
      final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
      if (payloadWorkspaceId != workspaceId) {
        continue;
      }
      switch (action.type) {
        case OfflineActionTypes.archiveExpense:
          final expenseId = '${action.payload['expenseId'] ?? ''}';
          if (expenseId.isNotEmpty) {
            archivedIds.add(expenseId);
          }
          break;
        default:
          break;
      }
    }

    if (archivedIds.isNotEmpty) {
      items.removeWhere((item) => archivedIds.contains(item.id));
    }

    for (final action in actions) {
      if (action.type != OfflineActionTypes.updateExpense) {
        continue;
      }
      final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
      final payloadProjectId = '${action.payload['projectId'] ?? ''}';
      final expenseId = '${action.payload['expenseId'] ?? ''}';
      if (payloadWorkspaceId != workspaceId ||
          payloadProjectId != projectId ||
          expenseId.isEmpty) {
        continue;
      }
      final index = items.indexWhere((item) => item.id == expenseId);
      if (index < 0) {
        continue;
      }
      final current = items[index];
      items[index] = Expense(
        id: current.id,
        workspaceId: current.workspaceId,
        projectId: current.projectId,
        projectName: current.projectName,
        category: '${action.payload['category'] ?? current.category}',
        amount:
            (action.payload['amount'] as num?)?.toDouble() ?? current.amount,
        currency: current.currency,
        date:
            DateTime.tryParse('${action.payload['date'] ?? ''}') ??
            current.date,
        notes: '${action.payload['notes'] ?? current.notes}',
        supplierName:
            '${action.payload['supplierName'] ?? current.supplierName}',
        paymentMethod:
            '${action.payload['paymentMethod'] ?? current.paymentMethod}',
        inputMethod: current.inputMethod,
        transcript: current.transcript,
        source: current.source,
        storagePath: current.storagePath,
        isArchived: current.isArchived,
        clientMutationId: current.clientMutationId,
      );
    }

    if (includePendingCreates) {
      final liveMutationIds = items
          .map((item) => item.clientMutationId)
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final action in actions) {
        if (action.type != OfflineActionTypes.createExpense) {
          continue;
        }
        final clientMutationId = '${action.payload['clientMutationId'] ?? ''}';
        if (clientMutationId.isNotEmpty &&
            liveMutationIds.contains(clientMutationId)) {
          continue;
        }
        final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
        final payloadProjectId = '${action.payload['projectId'] ?? ''}';
        if (payloadWorkspaceId != workspaceId ||
            payloadProjectId != projectId) {
          continue;
        }
        items.insert(0, _expenseFromCreateAction(action));
      }
    }

    final deduped = <String, Expense>{};
    for (final item in items) {
      deduped[item.id] = item;
    }
    final result = deduped.values.toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  Expense _expenseFromCreateAction(OfflineAction action) {
    final payload = action.payload;
    final parsedDate = DateTime.tryParse('${payload['date'] ?? ''}');
    return Expense(
      id: 'pending_${action.id}',
      workspaceId: '${payload['workspaceId'] ?? ''}',
      projectId: '${payload['projectId'] ?? ''}',
      projectName: '${payload['projectName'] ?? ''}',
      category: '${payload['category'] ?? 'other'}',
      amount: (payload['amount'] as num?)?.toDouble() ?? 0,
      currency: '${payload['currency'] ?? 'EGP'}',
      date: parsedDate ?? action.createdAt,
      notes: '${payload['notes'] ?? ''}',
      supplierName: '${payload['supplierName'] ?? ''}',
      paymentMethod: '${payload['paymentMethod'] ?? ''}',
      inputMethod: 'manual',
      transcript: '',
      source: 'pending',
      storagePath: '',
      isArchived: false,
      clientMutationId: '${payload['clientMutationId'] ?? action.id}',
    );
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return FirebaseExpenseRepository(
    ref.watch(firestoreProvider),
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
  );
});
