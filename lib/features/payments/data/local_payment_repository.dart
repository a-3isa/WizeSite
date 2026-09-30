part of 'payment_repository.dart';

/// Payment reads from the local PowerSync replica (spec 004, tasks.md T044).
/// Payments live in the financial sync bucket, so a plain member's replica has
/// none, matching `canAccessAccounting` in firestore.rules. Overlay and filter
/// semantics are the inherited private helpers; writes are inherited.
class LocalPaymentRepository extends FirebasePaymentRepository {
  LocalPaymentRepository(
    super.firestore,
    super.mutationService,
    super.queue,
    this._db,
  );

  final Future<PowerSyncDatabase> _db;

  PaymentRecord _fromRow(LocalRow row) =>
      PaymentRecord.fromMap('${row['id']}', localRowToMap('payments', row));

  @override
  Stream<List<PaymentRecord>> watchPayments(
    String workspaceId, {
    String? projectId,
  }) {
    final byProject = projectId != null && projectId.isNotEmpty;
    return combineWithQueue(
      rows: watchLocalRows(
        _db,
        'SELECT * FROM payments WHERE workspace_id = ? AND is_archived = 0'
        '${byProject ? ' AND project_id = ?' : ''} '
        'ORDER BY date DESC, id DESC LIMIT 24',
        [workspaceId, if (byProject) projectId],
      ),
      queue: _queue,
      combine: (rows, actions) => _applyPendingPayments(
        baseItems: [for (final row in rows) _fromRow(row)],
        actions: actions,
        workspaceId: workspaceId,
        projectId: projectId,
        includePendingCreates: true,
      ),
    );
  }

  @override
  Future<FirestorePage<PaymentRecord>> fetchPaymentsPage(
    String workspaceId, {
    String? projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    Object? cursor,
    int pageSize = 20,
  }) async {
    final where = <String>['workspace_id = ?', 'is_archived = 0'];
    final args = <Object?>[workspaceId];
    if (projectId != null && projectId.isNotEmpty) {
      where.add('project_id = ?');
      args.add(projectId);
    }
    if (entityId != null && entityId.isNotEmpty) {
      where.add('entity_id = ?');
      args.add(entityId);
    } else if (entityName != null && entityName.trim().isNotEmpty) {
      where.add('entity_name = ?');
      args.add(entityName.trim());
    }
    for (final (column, value) in [
      ('entity_type', entityType),
      ('payment_method', paymentMethod),
      ('payment_status', paymentStatus),
    ]) {
      if (value != null && value.isNotEmpty) {
        where.add('$column = ?');
        args.add(value);
      }
    }
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
      'SELECT * FROM payments WHERE ${where.join(' AND ')} '
      'ORDER BY date DESC, id DESC LIMIT ?',
      [...args, pageSize],
    );
    final actions = await _queue.list();
    final items =
        _applyPendingPayments(
              baseItems: [for (final row in rows) _fromRow(row)],
              actions: actions,
              workspaceId: workspaceId,
              projectId: projectId,
              includePendingCreates: cursor == null,
            )
            .where(
              (payment) => _matchesPaymentFilters(
                payment,
                entityId: entityId,
                entityName: entityName,
                entityType: entityType,
                paymentMethod: paymentMethod,
                paymentStatus: paymentStatus,
                searchText: searchText,
                startDate: startDate,
                endDate: endDate,
              ),
            )
            .toList(growable: false);
    final last = rows.isEmpty ? null : rows.last;
    return FirestorePage<PaymentRecord>(
      items: items,
      hasMore: rows.length == pageSize,
      nextCursor: last == null
          ? cursor
          : LocalPageCursor(sortValue: last['date'], id: '${last['id']}'),
    );
  }

  @override
  Future<PaymentRecord?> getPayment(String paymentId) async {
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM payments WHERE id = ?',
      [paymentId],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }
}
