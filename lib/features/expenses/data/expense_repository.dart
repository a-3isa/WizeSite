import 'package:buildtrack_app/core/pagination/local_page.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

abstract interface class ExpenseRepository {
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId);
  Future<RecordPage<Expense>> fetchExpensesPage(
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
    List<Map<String, dynamic>>? items,
    String inputMethod = 'manual',
    String? transcript,
    String? source,
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
    List<Map<String, dynamic>>? items,
  });

  Future<MutationResult> archiveExpense(String expenseId);
}

// Expenses read from the local PowerSync replica (spec 004, T043); pending
/// queue actions are overlaid on the rows. Writes are queued RPCs.
class LocalExpenseRepository implements ExpenseRepository {
  LocalExpenseRepository(this._mutationService, this._queue, this._db);

  final WorkspaceMutationService _mutationService;
  final OfflineActionQueue _queue;
  final Future<PowerSyncDatabase> _db;

  Expense _fromRow(LocalRow row) =>
      Expense.fromMap('${row['id']}', localRowToMap('expenses', row));

  @override
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId) {
    return combineWithQueue(
      rows: watchLocalRows(
        _db,
        'SELECT * FROM expenses WHERE workspace_id = ? AND project_id = ? '
        'AND is_archived = 0 ORDER BY date DESC, id DESC LIMIT 24',
        [workspaceId, projectId],
      ),
      queue: _queue,
      combine: (rows, actions) => _applyPendingExpenses(
        baseItems: [for (final row in rows) _fromRow(row)],
        actions: actions,
        workspaceId: workspaceId,
        projectId: projectId,
        includePendingCreates: true,
      ),
    );
  }

  @override
  Future<RecordPage<Expense>> fetchExpensesPage(
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
    final where = <String>[
      'workspace_id = ?',
      'project_id = ?',
      'is_archived = 0',
    ];
    final args = <Object?>[workspaceId, projectId];
    if (entityId != null && entityId.isNotEmpty) {
      where.add('entity_id = ?');
      args.add(entityId);
    } else if (entityName != null && entityName.trim().isNotEmpty) {
      where.add('supplier_name = ?');
      args.add(entityName.trim());
    }
    for (final (column, value) in [
      ('category', category),
      ('entity_type', entityType),
      ('payment_method', paymentMethod),
      ('payment_status', paymentStatus),
    ]) {
      if (value != null && value.isNotEmpty) {
        where.add('$column = ?');
        args.add(value);
      }
    }
    // julianday() parses both the replica's timestamp text and ISO-8601.
    if (startDate != null) {
      where.add('julianday(date) >= julianday(?)');
      args.add(startDate.toUtc().toIso8601String());
    }
    if (endDate != null) {
      where.add('julianday(date) <= julianday(?)');
      args.add(endDate.toUtc().toIso8601String());
    }
    final keyset = cursor as LocalPageCursor?;
    if (keyset != null) {
      where.add('(date < ? OR (date = ? AND id < ?))');
      args.addAll([keyset.sortValue, keyset.sortValue, keyset.id]);
    }
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM expenses WHERE ${where.join(' AND ')} '
      'ORDER BY date DESC, id DESC LIMIT ?',
      [...args, pageSize],
    );
    final actions = await _queue.list();
    final items =
        _applyPendingExpenses(
              baseItems: [for (final row in rows) _fromRow(row)],
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
    final last = rows.isEmpty ? null : rows.last;
    return RecordPage<Expense>(
      items: items,
      hasMore: rows.length == pageSize,
      nextCursor: last == null
          ? cursor
          : LocalPageCursor(sortValue: last['date'], id: '${last['id']}'),
    );
  }

  @override
  Future<Expense?> getExpense(String expenseId) async {
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM expenses WHERE id = ?',
      [expenseId],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
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
    List<Map<String, dynamic>>? items,
    String inputMethod = 'manual',
    String? transcript,
    String? source,
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
      items: items,
      inputMethod: inputMethod,
      transcript: transcript,
      source: source,
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
    List<Map<String, dynamic>>? items,
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
      items: items,
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
        items: action.payload.containsKey('items')
            ? ExpenseItem.listFromDynamic(action.payload['items'])
            : current.items,
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
      // Feature 005 (FR-024): the receipt's item names are searchable too.
      ...expense.items.map((item) => item.name),
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
      inputMethod: '${payload['inputMethod'] ?? 'manual'}',
      transcript: '',
      source: 'pending',
      storagePath: '',
      attachments:
          (payload['attachments'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Attachment.fromMap)
              .toList() ??
          const <Attachment>[],
      // Queued by an app build older than feature 005: no items (legacy).
      items: ExpenseItem.listFromDynamic(payload['items']),
      isArchived: false,
      clientMutationId: '${payload['clientMutationId'] ?? action.id}',
    );
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return LocalExpenseRepository(
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
    ref.watch(localDatabaseProvider),
  );
});
