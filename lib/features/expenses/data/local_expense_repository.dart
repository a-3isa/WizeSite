part of 'expense_repository.dart';

/// Expense reads from the local PowerSync replica (spec 004, tasks.md T043).
/// Overlay and filter semantics are the inherited private helpers; writes are
/// inherited unchanged.
class LocalExpenseRepository extends FirebaseExpenseRepository {
  LocalExpenseRepository(
    super.firestore,
    super.mutationService,
    super.queue,
    this._db,
  );

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
    return FirestorePage<Expense>(
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
}
