part of 'project_repository.dart';

/// Project reads from the local PowerSync replica (spec 004, tasks.md T042).
///
/// Only the data source changes: the optimistic offline overlay, ordering and
/// pagination semantics are the inherited private helpers of
/// [FirebaseProjectRepository]. Writes are inherited unchanged (they already
/// go through the RPC/offline-queue path).
class LocalProjectRepository extends FirebaseProjectRepository {
  LocalProjectRepository(
    super.firestore,
    super.mutationService,
    super.queue,
    this._db,
  );

  final Future<PowerSyncDatabase> _db;

  static const _selectWithMetrics =
      'SELECT p.*, m.payload AS metrics_payload '
      'FROM projects p LEFT JOIN project_metrics m ON m.id = p.id';

  static List<Map<String, Object?>> _asMaps(
    Iterable<Map<String, dynamic>> rows,
  ) => [for (final row in rows) Map<String, Object?>.from(row)];

  /// Row → Project, merging the metrics payload exactly as the Firestore
  /// repository merges the `project_metrics` document.
  Project _fromRow(Map<String, Object?> row) {
    final projectRow = Map<String, Object?>.from(row)
      ..remove('metrics_payload');
    final metrics = row['metrics_payload'] == null
        ? null
        : localRowToMap('project_metrics', {'payload': row['metrics_payload']});
    return Project.fromMap(
      '${row['id']}',
      mergeProjectMetricsData(
        projectData: localRowToMap('projects', projectRow),
        metricsData: metrics,
      ),
    );
  }

  Stream<List<Project>> _watchLocal({
    required String where,
    required List<Object?> args,
    required String workspaceId,
    required bool includePendingCreates,
    int? maxResults,
  }) {
    final limit = maxResults == null ? '' : ' LIMIT $maxResults';
    // A fresh replica query per listener: Stream.multi may be listened to
    // more than once, and each watch stream is single-subscription.
    Stream<List<Map<String, Object?>>> rows() => Stream.fromFuture(_db)
        .asyncExpand(
          (db) => db.watch(
            '$_selectWithMetrics WHERE $where '
            'ORDER BY p.created_at DESC, p.id DESC$limit',
            parameters: args,
          ),
        )
        .map(_asMaps);
    return Stream.multi((controller) {
      List<Project>? current;
      List<OfflineAction> actions = const [];
      void emit() {
        final base = current;
        if (base == null) return;
        controller.add(
          _applyOptimisticProjectList(
            baseItems: base,
            actions: actions,
            workspaceId: workspaceId,
            includePendingCreates: includePendingCreates,
          ),
        );
      }

      final rowSub = rows().listen((result) {
        try {
          current = [for (final row in result) _fromRow(row)];
          emit();
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        }
      }, onError: controller.addError);
      final queueSub = _queue.watch(includeExpiredSynced: true).listen((next) {
        actions = next;
        emit();
      }, onError: controller.addError);
      // Not awaited: a consumer (e.g. `.first`) must not wait for the replica
      // query or the queue watcher to finish tearing down.
      controller.onCancel = () {
        unawaited(rowSub.cancel());
        unawaited(queueSub.cancel());
      };
    });
  }

  @override
  Future<bool> hasAnyPayment(String projectId) async {
    final db = await _db;
    final synced = await db.getOptional(
      'SELECT 1 FROM payments WHERE project_id = ? AND is_archived = 0 LIMIT 1',
      [projectId],
    );
    if (synced != null) return true;
    final pending = await _queue.list();
    return pending.any(
      (action) =>
          action.type == OfflineActionTypes.createPayment &&
          '${action.payload['projectId'] ?? ''}' == projectId,
    );
  }

  @override
  Stream<List<Project>> watchProjects(String workspaceId) => _watchLocal(
    where: 'p.workspace_id = ? AND p.is_archived = 0',
    args: [workspaceId],
    workspaceId: workspaceId,
    includePendingCreates: true,
    maxResults: 50,
  );

  @override
  Stream<List<Project>> watchAllProjects(String workspaceId) => _watchLocal(
    where: 'p.workspace_id = ?',
    args: [workspaceId],
    workspaceId: workspaceId,
    includePendingCreates: true,
  );

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) =>
      _watchLocal(
        where: 'p.workspace_id = ? AND p.is_archived = 1',
        args: [workspaceId],
        workspaceId: workspaceId,
        includePendingCreates: false,
      );

  @override
  Stream<Project?> watchProject(String projectId) {
    if (projectId.startsWith('pending_')) {
      return super.watchProject(projectId); // queue-only, no backend read
    }
    Stream<List<Map<String, Object?>>> rows() => Stream.fromFuture(_db)
        .asyncExpand(
          (db) => db.watch(
            '$_selectWithMetrics WHERE p.id = ?',
            parameters: [projectId],
          ),
        )
        .map(_asMaps);
    return Stream.multi((controller) {
      Project? current;
      var loaded = false;
      List<OfflineAction> actions = const [];
      void emit() {
        if (!loaded) return;
        final project = current;
        controller.add(
          project == null ? null : _applyPendingDeltas(project, actions),
        );
      }

      final rowSub = rows().listen((result) {
        try {
          loaded = true;
          current = result.isEmpty ? null : _fromRow(result.first);
          emit();
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        }
      }, onError: controller.addError);
      final queueSub = _queue.watch(includeExpiredSynced: true).listen((next) {
        actions = next;
        emit();
      }, onError: controller.addError);
      // Not awaited: a consumer (e.g. `.first`) must not wait for the replica
      // query or the queue watcher to finish tearing down.
      controller.onCancel = () {
        unawaited(rowSub.cancel());
        unawaited(queueSub.cancel());
      };
    });
  }

  @override
  Future<Project?> getProject(String projectId) async {
    final db = await _db;
    final row = await db.getOptional('$_selectWithMetrics WHERE p.id = ?', [
      projectId,
    ]);
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
  }) => _pageWithSortValue(
    workspaceId: workspaceId,
    where: 'p.workspace_id = ? AND p.is_archived = 0',
    args: [workspaceId],
    sortExpression: 'p.created_at',
    descending: true,
    pageSize: pageSize,
    cursor: cursor,
    includePendingCreates: cursor == null,
  );

  @override
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
  }) => _pageWithSortValue(
    workspaceId: workspaceId,
    where: 'p.workspace_id = ? AND p.is_archived = 1',
    args: [workspaceId],
    sortExpression: 'p.created_at',
    descending: true,
    pageSize: pageSize,
    cursor: cursor,
    includePendingCreates: false,
  );

  @override
  Future<FirestorePage<Project>> fetchProjectBrowsePage(
    ProjectBrowseQuery request, {
    Object? cursor,
  }) {
    final filters = <String>['p.workspace_id = ?'];
    final args = <Object?>[request.workspaceId];
    if (!request.includeArchived) filters.add('p.is_archived = 0');
    if (request.status != null && request.status!.isNotEmpty) {
      filters.add('p.status = ?');
      args.add(request.status);
    }
    final (sortExpression, descending) = switch (request.sort) {
      ProjectBrowseSort.name => ('p.name', false),
      ProjectBrowseSort.recent => ('p.created_at', true),
      // Financial sorts read the recompute output, like the Firestore query
      // on project_metrics. Projects without metrics sort last.
      ProjectBrowseSort.highestExpense => (
        "COALESCE(json_extract(m.payload, '\$.totalExpenses'), -1e18)",
        true,
      ),
      ProjectBrowseSort.highestIncome => (
        "COALESCE(json_extract(m.payload, '\$.totalIncome'), -1e18)",
        true,
      ),
      ProjectBrowseSort.highestNet => (
        "COALESCE(json_extract(m.payload, '\$.net'), -1e18)",
        true,
      ),
    };
    return _pageWithSortValue(
      workspaceId: request.workspaceId,
      where: filters.join(' AND '),
      args: args,
      sortExpression: sortExpression,
      descending: descending,
      pageSize: request.pageSize,
      cursor: cursor,
      includePendingCreates:
          cursor == null &&
          !request.includeArchived &&
          !request.sort.isFinancial,
    );
  }

  /// [_page] ordered by an arbitrary SQL expression, exposed as `sort_value`
  /// so the keyset cursor can compare against it.
  Future<FirestorePage<Project>> _pageWithSortValue({
    required String workspaceId,
    required String where,
    required List<Object?> args,
    required String sortExpression,
    required bool descending,
    required int pageSize,
    required Object? cursor,
    required bool includePendingCreates,
  }) {
    return _pageFrom(
      select:
          'SELECT * FROM (SELECT p.*, m.payload AS metrics_payload, '
          '$sortExpression AS sort_value FROM projects p '
          'LEFT JOIN project_metrics m ON m.id = p.id WHERE $where) p',
      args: args,
      workspaceId: workspaceId,
      descending: descending,
      pageSize: pageSize,
      cursor: cursor,
      includePendingCreates: includePendingCreates,
    );
  }

  Future<FirestorePage<Project>> _pageFrom({
    required String select,
    required List<Object?> args,
    required String workspaceId,
    required bool descending,
    required int pageSize,
    required Object? cursor,
    required bool includePendingCreates,
  }) async {
    final db = await _db;
    final keyset = cursor as LocalPageCursor?;
    final op = descending ? '<' : '>';
    final direction = descending ? 'DESC' : 'ASC';
    final params = [...args];
    var keysetSql = '';
    if (keyset != null) {
      keysetSql =
          ' WHERE (p.sort_value $op ? OR (p.sort_value = ? AND p.id $op ?))';
      params.addAll([keyset.sortValue, keyset.sortValue, keyset.id]);
    }
    params.add(pageSize + 1);
    final result = await db.getAll(
      '$select$keysetSql ORDER BY p.sort_value $direction, p.id $direction '
      'LIMIT ?',
      params,
    );
    final rows = [for (final row in result) Map<String, Object?>.from(row)];
    final hasMore = rows.length > pageSize;
    final pageRows = hasMore ? rows.sublist(0, pageSize) : rows;
    final actions = await _queue.list(includeExpiredSynced: true);
    final items = _applyOptimisticProjectList(
      baseItems: [
        for (final row in pageRows)
          _fromRow(Map<String, Object?>.from(row)..remove('sort_value')),
      ],
      actions: actions,
      workspaceId: workspaceId,
      includePendingCreates: includePendingCreates,
    );
    final last = pageRows.isEmpty ? null : pageRows.last;
    return FirestorePage<Project>(
      items: items,
      hasMore: hasMore,
      nextCursor: last == null
          ? cursor
          : LocalPageCursor(sortValue: last['sort_value'], id: '${last['id']}'),
    );
  }
}
