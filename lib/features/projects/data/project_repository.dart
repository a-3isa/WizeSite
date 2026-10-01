import 'dart:async';

import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/pagination/local_page.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/features/projects/data/project_metrics_merger.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

enum ProjectBrowseSort {
  recent,
  name,
  highestExpense,
  highestIncome,
  highestNet;

  bool get isFinancial => switch (this) {
    highestExpense || highestIncome || highestNet => true,
    recent || name => false,
  };
}

class ProjectBrowseQuery {
  const ProjectBrowseQuery({
    required this.workspaceId,
    this.status,
    this.includeArchived = false,
    this.sort = ProjectBrowseSort.recent,
    this.pageSize = 20,
  });

  final String workspaceId;
  final String? status;
  final bool includeArchived;
  final ProjectBrowseSort sort;
  final int pageSize;
}

abstract interface class ProjectBrowseRepository {
  Future<FirestorePage<Project>> fetchProjectBrowsePage(
    ProjectBrowseQuery request, {
    Object? cursor,
  });
}

abstract interface class ProjectRepository {
  Stream<List<Project>> watchProjects(String workspaceId);
  Stream<List<Project>> watchAllProjects(String workspaceId);
  Stream<List<Project>> watchArchivedProjects(String workspaceId);
  Stream<Project?> watchProject(String projectId);
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
  });
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
  });
  Future<MutationResult> createProject({
    required String workspaceId,
    required String userId,
    required String name,
    required String clientName,
    double? contractValue,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    double completionPercentage,
  });

  Future<Project?> getProject(String projectId);

  Future<void> updateProject({
    required String projectId,
    required String name,
    required String clientName,
    double? contractValue,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    double? completionPercentage,
    String? status,
  });

  Future<void> archiveProject(String projectId);
  Future<void> unarchiveProject(String projectId);
  Future<void> deleteProject(String projectId);

  /// Whether any payment record exists against [projectId].
  ///
  /// Backs the core invariant: a project with no Contract Value cannot hold
  /// payments, so clearing a Contract Value is refused while one exists.
  ///
  /// Keyed on record *existence*, never on the payment total — a zero-amount
  /// or refunded payment still leaves a record that would otherwise be
  /// orphaned. Counts payments still queued offline for the same reason.
  Future<bool> hasAnyPayment(String projectId);
}

/// Projects read from the local PowerSync replica (spec 004, T042), with
/// the metrics row merged in and pending queue actions overlaid. Writes go
/// through the RPC/offline-queue path.
class LocalProjectRepository
    implements ProjectRepository, ProjectBrowseRepository {
  LocalProjectRepository(this._mutationService, this._queue, this._db);

  final WorkspaceMutationService _mutationService;
  final OfflineActionQueue _queue;
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
      return _watchPendingProject(projectId); // queue only
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

  /// A project created offline, from its queued create action.
  Stream<Project?> _watchPendingProject(String projectId) {
    return _queue.watch(includeExpiredSynced: true).map((actions) {
      for (final action in actions) {
        if (action.type != OfflineActionTypes.createProject) {
          continue;
        }
        if ('pending_${action.id}' == projectId) {
          return _projectFromCreateAction(action);
        }
      }
      return null;
    });
  }

  @override
  Future<MutationResult> createProject({
    required String workspaceId,
    required String userId,
    required String name,
    required String clientName,
    double? contractValue,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    double completionPercentage = 0,
  }) async {
    return _mutationService.createProject(
      workspaceId: workspaceId,
      name: name,
      clientName: clientName,
      contractValue: contractValue,
      startDate: startDate,
      expectedEndDate: expectedEndDate,
      location: location,
      description: description,
      budgetLimit: budgetLimit,
      completionPercentage: completionPercentage,
    );
  }

  @override
  Future<void> updateProject({
    required String projectId,
    required String name,
    required String clientName,
    double? contractValue,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    double? completionPercentage,
    String? status,
  }) async {
    final project = await getProject(projectId);
    if (project == null) {
      return;
    }
    await _mutationService.updateProject(
      workspaceId: project.workspaceId,
      projectId: projectId,
      name: name,
      clientName: clientName,
      contractValue: contractValue,
      completionPercentage: completionPercentage ?? 0,
      startDate: startDate,
      expectedEndDate: expectedEndDate,
      location: location,
      description: description,
      budgetLimit: budgetLimit,
      status: status ?? 'active',
    );
  }

  @override
  Future<void> archiveProject(String projectId) async {
    final project = await getProject(projectId);
    if (project == null) {
      return;
    }
    await _mutationService.archiveProject(
      workspaceId: project.workspaceId,
      projectId: projectId,
    );
  }

  @override
  Future<void> unarchiveProject(String projectId) async {
    final project = await getProject(projectId);
    if (project == null) {
      return;
    }
    await _mutationService.unarchiveProject(
      workspaceId: project.workspaceId,
      projectId: projectId,
    );
  }

  @override
  Future<void> deleteProject(String projectId) async {
    final project = await getProject(projectId);
    if (project == null) {
      return;
    }
    await _mutationService.deleteProjectCascade(
      workspaceId: project.workspaceId,
      projectId: projectId,
    );
  }

  List<Project> _applyOptimisticProjectList({
    required List<Project> baseItems,
    required List<OfflineAction> actions,
    required String workspaceId,
    required bool includePendingCreates,
  }) {
    final items = baseItems
        .map((project) => _applyPendingDeltas(project, actions))
        .toList(growable: true);

    final archivedProjectIds = actions
        .where(
          (action) =>
              action.type == OfflineActionTypes.archiveProject &&
              '${action.payload['workspaceId'] ?? ''}' == workspaceId,
        )
        .map((action) => '${action.payload['projectId'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toSet();
    items.removeWhere((project) => archivedProjectIds.contains(project.id));

    final unarchivedProjectIds = actions
        .where(
          (action) =>
              action.type == OfflineActionTypes.unarchiveProject &&
              '${action.payload['workspaceId'] ?? ''}' == workspaceId,
        )
        .map((action) => '${action.payload['projectId'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (!includePendingCreates) {
      items.removeWhere((project) => unarchivedProjectIds.contains(project.id));
    }

    final deletedProjectIds = actions
        .where(
          (action) =>
              action.type == OfflineActionTypes.deleteProject &&
              '${action.payload['workspaceId'] ?? ''}' == workspaceId,
        )
        .map((action) => '${action.payload['projectId'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toSet();
    items.removeWhere((project) => deletedProjectIds.contains(project.id));

    for (final action in actions) {
      if (action.type != OfflineActionTypes.updateProject ||
          '${action.payload['workspaceId'] ?? ''}' != workspaceId) {
        continue;
      }
      final projectId = '${action.payload['projectId'] ?? ''}';
      final index = items.indexWhere((project) => project.id == projectId);
      if (index < 0) {
        continue;
      }
      final current = items[index];
      items[index] = Project(
        id: current.id,
        workspaceId: current.workspaceId,
        name: '${action.payload['name'] ?? current.name}',
        clientName: '${action.payload['clientName'] ?? current.clientName}',
        contractValue: action.payload.containsKey('contractValue')
            ? (action.payload['contractValue'] as num?)?.toDouble()
            : current.contractValue,
        status: '${action.payload['status'] ?? current.status}',
        completionPercentage:
            (action.payload['completionPercentage'] as num?)?.toDouble() ??
            current.completionPercentage,
        totalExpenses: current.totalExpenses,
        totalPayments: current.totalPayments,
        netProfit: current.netProfit,
        isArchived: current.isArchived,
        clientMutationId: current.clientMutationId,
        location: '${action.payload['location'] ?? current.location}',
        description: '${action.payload['description'] ?? current.description}',
        budgetLimit:
            (action.payload['budgetLimit'] as num?)?.toDouble() ??
            current.budgetLimit,
        startDate: current.startDate,
        expectedEndDate: current.expectedEndDate,
      );
    }

    if (includePendingCreates) {
      final pendingProjects = <Project>[];
      final liveMutationIds = items
          .map((item) => item.clientMutationId)
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final action in actions) {
        if (action.type != OfflineActionTypes.createProject) {
          continue;
        }
        if ('${action.payload['workspaceId'] ?? ''}' != workspaceId) {
          continue;
        }
        final clientMutationId = '${action.payload['clientMutationId'] ?? ''}';
        if (clientMutationId.isNotEmpty &&
            liveMutationIds.contains(clientMutationId)) {
          continue;
        }
        pendingProjects.add(_projectFromCreateAction(action));
      }
      items.insertAll(0, pendingProjects);
    }

    final unique = <String, Project>{};
    for (final project in items) {
      unique[project.id] = project;
    }
    return unique.values.toList(growable: false);
  }

  Project _applyPendingDeltas(Project project, List<OfflineAction> actions) {
    var totalExpenses = project.totalExpenses;
    var totalPayments = project.totalPayments;

    for (final action in actions) {
      final payloadProjectId = '${action.payload['projectId'] ?? ''}';
      final previousProjectId = '${action.payload['previousProjectId'] ?? ''}';
      if (payloadProjectId != project.id && previousProjectId != project.id) {
        continue;
      }
      switch (action.type) {
        case OfflineActionTypes.createExpense:
          final delta = ((action.payload['amount'] as num?) ?? 0).toDouble();
          if (!_isDeltaAlreadyReflected(
            action: action,
            baselineField: 'projectTotalExpensesBefore',
            currentTotal: totalExpenses,
            delta: delta,
          )) {
            totalExpenses += delta;
          }
          break;
        case OfflineActionTypes.updateExpense:
          final delta =
              (((action.payload['amount'] as num?) ?? 0) -
                      ((action.payload['previousAmount'] as num?) ?? 0))
                  .toDouble();
          if (!_isDeltaAlreadyReflected(
            action: action,
            baselineField: 'projectTotalExpensesBefore',
            currentTotal: totalExpenses,
            delta: delta,
          )) {
            totalExpenses += delta;
          }
          break;
        case OfflineActionTypes.createWorkerEntry:
          final daysWorked = (action.payload['daysWorked'] as num?) ?? 0;
          final dailyWage = (action.payload['dailyWage'] as num?) ?? 0;
          final delta = (daysWorked * dailyWage).toDouble();
          if (!_isDeltaAlreadyReflected(
            action: action,
            baselineField: 'projectTotalExpensesBefore',
            currentTotal: totalExpenses,
            delta: delta,
          )) {
            totalExpenses += delta;
          }
          break;
        case OfflineActionTypes.updateWorkerEntry:
          final previousProjectId =
              '${action.payload['previousProjectId'] ?? project.id}';
          num delta = 0;
          if (previousProjectId == project.id) {
            delta -=
                (action.payload['previousTotalCost'] as num?) ??
                (((action.payload['previousDaysWorked'] as num?) ?? 0) *
                    ((action.payload['previousDailyWage'] as num?) ?? 0));
          }
          if (payloadProjectId == project.id) {
            delta +=
                (action.payload['totalCost'] as num?) ??
                (((action.payload['daysWorked'] as num?) ?? 0) *
                    ((action.payload['dailyWage'] as num?) ?? 0));
          }
          final expenseDelta = delta.toDouble();
          if (!_isDeltaAlreadyReflected(
            action: action,
            baselineField: 'projectTotalExpensesBefore',
            currentTotal: totalExpenses,
            delta: expenseDelta,
          )) {
            totalExpenses += expenseDelta;
          }
          break;
        case OfflineActionTypes.createPayment:
          final delta = ((action.payload['amount'] as num?) ?? 0).toDouble();
          final reflected = _isDeltaAlreadyReflected(
            action: action,
            baselineField: 'projectTotalPaymentsBefore',
            currentTotal: totalPayments,
            delta: delta,
          );
          if (!reflected) {
            totalPayments += delta;
          }
          break;
        case OfflineActionTypes.updatePayment:
          final delta =
              (((action.payload['amount'] as num?) ?? 0) -
                      ((action.payload['previousAmount'] as num?) ?? 0))
                  .toDouble();
          if (!_isDeltaAlreadyReflected(
            action: action,
            baselineField: 'projectTotalPaymentsBefore',
            currentTotal: totalPayments,
            delta: delta,
          )) {
            totalPayments += delta;
          }
          break;
        default:
          break;
      }
    }

    if (totalExpenses == project.totalExpenses &&
        totalPayments == project.totalPayments) {
      return project;
    }

    return Project(
      id: project.id,
      workspaceId: project.workspaceId,
      name: project.name,
      clientName: project.clientName,
      contractValue: project.contractValue,
      status: project.status,
      completionPercentage: project.completionPercentage,
      totalExpenses: totalExpenses,
      totalPayments: totalPayments,
      netProfit: totalPayments - totalExpenses,
      isArchived: project.isArchived,
      clientMutationId: project.clientMutationId,
      location: project.location,
      description: project.description,
      budgetLimit: project.budgetLimit,
      startDate: project.startDate,
      expectedEndDate: project.expectedEndDate,
    );
  }

  bool _isDeltaAlreadyReflected({
    required OfflineAction action,
    required String baselineField,
    required double currentTotal,
    required double delta,
  }) {
    final baseline = (action.payload[baselineField] as num?)?.toDouble();
    if (baseline == null || delta == 0) {
      return false;
    }
    final expected =
        (action.payload[baselineField.replaceFirst('Before', 'After')] as num?)
            ?.toDouble() ??
        baseline + delta;
    final reflected = delta > 0
        ? currentTotal >= expected
        : currentTotal <= expected;
    return reflected;
  }

  Project _projectFromCreateAction(OfflineAction action) {
    return Project(
      id: 'pending_${action.id}',
      workspaceId: '${action.payload['workspaceId'] ?? ''}',
      name: '${action.payload['name'] ?? ''}',
      clientName: '${action.payload['clientName'] ?? ''}',
      // No `?? 0`: an optimistic placeholder must not invent a contract amount
      // the user never entered.
      contractValue: (action.payload['contractValue'] as num?)?.toDouble(),
      status: 'active',
      completionPercentage:
          (action.payload['completionPercentage'] as num?)?.toDouble() ?? 0,
      totalExpenses: 0,
      totalPayments: 0,
      netProfit: 0,
      isArchived: false,
      clientMutationId: '${action.payload['clientMutationId'] ?? action.id}',
      location: '${action.payload['location'] ?? ''}',
      description: '${action.payload['description'] ?? ''}',
      budgetLimit: (action.payload['budgetLimit'] as num?)?.toDouble(),
      startDate: DateTime.tryParse('${action.payload['startDate'] ?? ''}'),
      expectedEndDate: DateTime.tryParse(
        '${action.payload['expectedEndDate'] ?? ''}',
      ),
    );
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return LocalProjectRepository(
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
    ref.watch(localDatabaseProvider),
  );
});
