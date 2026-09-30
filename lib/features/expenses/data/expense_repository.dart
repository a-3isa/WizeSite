import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/pagination/local_page.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

part 'local_expense_repository.dart';

abstract interface class ExpenseRepository {
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId);
  Future<FirestorePage<Expense>> fetchExpensesPage(
    String workspaceId, {
    required String projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? category,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    Object? cursor,
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
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    double? projectTotalExpensesBefore,
    List<Attachment>? attachments,
  });

  Future<void> updateExpense({
    required String expenseId,
    required String category,
    required double amount,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    List<Attachment>? attachments,
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
        .limit(24)
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
    String? entityId,
    String? entityName,
    String? entityType,
    String? category,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    Object? cursor,
    int pageSize = 20,
  }) async {
    final firestoreCursor = cursor as DocumentSnapshot<Map<String, dynamic>>?;
    var query = _firestore
        .collection('expenses')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .where('isArchived', isEqualTo: false);

    if (entityId != null && entityId.isNotEmpty) {
      query = query.where('entityId', isEqualTo: entityId);
    } else if (entityName != null && entityName.trim().isNotEmpty) {
      query = query.where('supplierName', isEqualTo: entityName.trim());
    }
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }
    if (entityType != null && entityType.isNotEmpty) {
      query = query.where('entityType', isEqualTo: entityType);
    }
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      query = query.where('paymentMethod', isEqualTo: paymentMethod);
    }
    if (paymentStatus != null && paymentStatus.isNotEmpty) {
      query = query.where('paymentStatus', isEqualTo: paymentStatus);
    }
    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('date', isLessThanOrEqualTo: endDate);
    }

    query = query.orderBy('date', descending: true).limit(pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(firestoreCursor!);
    }

    final snap = await query.get();
    final items = snap.docs
        .map((doc) => Expense.fromMap(doc.id, doc.data()))
        .toList();
    final actions = await _queue.list();
    final mergedItems =
        _applyPendingExpenses(
              baseItems: items,
              actions: actions,
              workspaceId: workspaceId,
              projectId: projectId,
              includePendingCreates: cursor == null,
            )
            .where(
              (expense) => _matchesExpenseFilters(
                expense,
                entityId: entityId,
                entityName: entityName,
                entityType: entityType,
                category: category,
                paymentMethod: paymentMethod,
                paymentStatus: paymentStatus,
                searchText: searchText,
                startDate: startDate,
                endDate: endDate,
              ),
            )
            .toList(growable: false);

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
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    double? projectTotalExpensesBefore,
    List<Attachment>? attachments,
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
      purpose: purpose,
      description: description,
      supplierName: supplierName,
      entityId: entityId,
      entityName: entityName,
      entityType: entityType,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      projectTotalExpensesBefore: projectTotalExpensesBefore,
      attachments: attachments?.map((item) => item.toMap()).toList(),
    );
  }

  @override
  Future<void> updateExpense({
    required String expenseId,
    required String category,
    required double amount,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    List<Attachment>? attachments,
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
      purpose: purpose,
      description: description,
      supplierName: supplierName,
      entityId: entityId,
      entityName: entityName,
      entityType: entityType,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      attachments:
          attachments?.map((item) => item.toMap()).toList() ??
          expense.attachments.map((item) => item.toMap()).toList(),
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
        purpose: '${action.payload['purpose'] ?? current.purpose}',
        description: '${action.payload['description'] ?? current.description}',
        supplierName:
            '${action.payload['supplierName'] ?? current.supplierName}',
        entityId:
            '${action.payload['entityId'] ?? current.entityId ?? ''}'.isNotEmpty
            ? '${action.payload['entityId'] ?? current.entityId ?? ''}'
            : null,
        entityName: '${action.payload['entityName'] ?? current.entityName}',
        entityType: '${action.payload['entityType'] ?? current.entityType}',
        paymentMethod:
            '${action.payload['paymentMethod'] ?? current.paymentMethod}',
        paymentStatus:
            '${action.payload['paymentStatus'] ?? current.paymentStatus}',
        inputMethod: current.inputMethod,
        transcript: current.transcript,
        source: current.source,
        storagePath: current.storagePath,
        attachments:
            (action.payload['attachments'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(Attachment.fromMap)
                .toList() ??
            current.attachments,
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

  bool _matchesExpenseFilters(
    Expense expense, {
    String? entityId,
    String? entityName,
    String? entityType,
    String? category,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (entityId != null &&
        entityId.isNotEmpty &&
        expense.entityId != entityId) {
      return false;
    }
    final normalizedEntityName = entityName?.trim().toLowerCase() ?? '';
    if ((entityId == null || entityId.isEmpty) &&
        normalizedEntityName.isNotEmpty) {
      final expenseEntityName = expense.entityName.trim().toLowerCase();
      final supplierName = expense.supplierName.trim().toLowerCase();
      if (expenseEntityName != normalizedEntityName &&
          supplierName != normalizedEntityName) {
        return false;
      }
    }
    if (category != null &&
        category.isNotEmpty &&
        expense.category != category) {
      return false;
    }
    if (entityType != null &&
        entityType.isNotEmpty &&
        expense.entityType != entityType) {
      return false;
    }
    if (paymentMethod != null &&
        paymentMethod.isNotEmpty &&
        expense.paymentMethod.toLowerCase() != paymentMethod.toLowerCase()) {
      return false;
    }
    if (paymentStatus != null &&
        paymentStatus.isNotEmpty &&
        expense.paymentStatus.toLowerCase() != paymentStatus.toLowerCase()) {
      return false;
    }
    final normalizedSearch = searchText?.trim().toLowerCase() ?? '';
    if (normalizedSearch.isNotEmpty &&
        !_containsAnyExpenseText(expense, normalizedSearch)) {
      return false;
    }
    if (startDate != null && expense.date.isBefore(startDate)) {
      return false;
    }
    if (endDate != null && expense.date.isAfter(endDate)) {
      return false;
    }
    return true;
  }

  bool _containsAnyExpenseText(Expense expense, String searchText) {
    return [
      expense.entityName,
      expense.supplierName,
      expense.description,
      expense.purpose,
      expense.notes,
    ].any((value) => value.toLowerCase().contains(searchText));
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
      purpose: '${payload['purpose'] ?? ''}',
      description: '${payload['description'] ?? payload['notes'] ?? ''}',
      supplierName: '${payload['supplierName'] ?? ''}',
      entityId:
          payload['entityId'] is String &&
              (payload['entityId'] as String).isNotEmpty
          ? payload['entityId'] as String
          : null,
      entityName: '${payload['entityName'] ?? ''}',
      entityType: '${payload['entityType'] ?? 'supplier'}',
      paymentMethod: '${payload['paymentMethod'] ?? ''}',
      paymentStatus: '${payload['paymentStatus'] ?? 'unpaid'}',
      inputMethod: 'manual',
      transcript: '',
      source: 'pending',
      storagePath: '',
      attachments:
          (payload['attachments'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Attachment.fromMap)
              .toList() ??
          const <Attachment>[],
      isArchived: false,
      clientMutationId: '${payload['clientMutationId'] ?? action.id}',
    );
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  if (BackendConfig.fromEnvironment.useSelfHostedBackend) {
    return LocalExpenseRepository(
      ref.watch(firestoreProvider),
      ref.watch(workspaceMutationServiceProvider),
      ref.watch(offlineActionQueueProvider),
      ref.watch(localDatabaseProvider),
    );
  }
  return FirebaseExpenseRepository(
    ref.watch(firestoreProvider),
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
  );
});
