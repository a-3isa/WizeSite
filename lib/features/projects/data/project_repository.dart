import 'dart:async';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/pagination/local_page.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/features/projects/data/project_metrics_merger.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

part 'local_project_repository.dart';

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

class FirebaseProjectRepository
    implements ProjectRepository, ProjectBrowseRepository {
  FirebaseProjectRepository(
    this._firestore,
    this._mutationService,
    this._queue,
  );

  final FirebaseFirestore _firestore;
  final WorkspaceMutationService _mutationService;
  final OfflineActionQueue _queue;

  @override
  Future<bool> hasAnyPayment(String projectId) async {
    // limit(1) existence probe — O(1), and no new index: two equality filters
    // are served by merging single-field indexes.
    //
    // Archived payments are excluded deliberately, matching the server guard:
    // archiving is the only removal this app offers, so counting archived
    // records would leave the user permanently unable to clear a contract they
    // were told to clear by removing payments.
    final synced = await _firestore
        .collection('payments')
        .where('projectId', isEqualTo: projectId)
        .where('isArchived', isEqualTo: false)
        .limit(1)
        .get();
    if (synced.docs.isNotEmpty) {
      return true;
    }
    // A payment still waiting to sync counts too, otherwise a user could clear
    // the contract offline and strand the queued payment on sync.
    final pending = await _queue.list();
    return pending.any(
      (action) =>
          action.type == OfflineActionTypes.createPayment &&
          '${action.payload['projectId'] ?? ''}' == projectId,
    );
  }

  @override
  Stream<List<Project>> watchProjects(String workspaceId) {
    // Newest 50 after a workspace filter. Equality + orderBy + limit hangs in
    // FakeFirestore and needs a composite index in prod for the warm stream.
    final query = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId);
    return _watchProjectQueryWithMetrics(
      query: query,
      workspaceId: workspaceId,
      includePendingCreates: true,
      excludeArchived: true,
      maxResults: 50,
    );
  }

  @override
  Stream<List<Project>> watchAllProjects(String workspaceId) {
    final query = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId);
    return _watchProjectQueryWithMetrics(
      query: query,
      workspaceId: workspaceId,
      includePendingCreates: true,
    );
  }

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) {
    final query = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: true);
    return _watchProjectQueryWithMetrics(
      query: query,
      workspaceId: workspaceId,
      includePendingCreates: false,
    );
  }

  @override
  Stream<Project?> watchProject(String projectId) {
    if (projectId.startsWith('pending_')) {
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

    final projectStream = _firestore
        .collection('projects')
        .doc(projectId)
        .snapshots();
    final metricsStream = _firestore
        .collection('project_metrics')
        .doc(projectId)
        .snapshots();
    final queueStream = _queue.watch(includeExpiredSynced: true);
    return Stream.multi((controller) {
      DocumentSnapshot<Map<String, dynamic>>? currentProjectSnap;
      Map<String, dynamic>? currentMetrics;
      List<OfflineAction> currentActions = const [];
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? projectSub;
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? metricsSub;
      StreamSubscription<List<OfflineAction>>? queueSub;
      var canceled = false;

      void emit() {
        if (canceled) {
          return;
        }
        final projectSnap = currentProjectSnap;
        if (projectSnap == null || !projectSnap.exists) {
          controller.add(null);
          return;
        }
        final baseProject = Project.fromMap(
          projectSnap.id,
          mergeProjectMetricsData(
            projectData: projectSnap.data() ?? const {},
            metricsData: currentMetrics,
          ),
        );
        controller.add(_applyPendingDeltas(baseProject, currentActions));
      }

      Future<void> start() async {
        currentActions = await _queue.list(includeExpiredSynced: true);
        if (canceled) {
          return;
        }
        projectSub = projectStream.listen((snapshot) {
          currentProjectSnap = snapshot;
          emit();
        }, onError: controller.addError);
        metricsSub = metricsStream.listen((snapshot) {
          currentMetrics = snapshot.exists ? snapshot.data() : null;
          emit();
        }, onError: controller.addError);
        queueSub = queueStream.listen((actions) {
          currentActions = actions;
          emit();
        }, onError: controller.addError);
      }

      unawaited(start());

      controller.onCancel = () async {
        canceled = true;
        await projectSub?.cancel();
        await metricsSub?.cancel();
        await queueSub?.cancel();
      };
    });
  }

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
  }) async {
    final firestoreCursor = cursor as DocumentSnapshot<Map<String, dynamic>>?;
    var query = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(firestoreCursor!);
    }

    final snap = await query.get();
    final metricsByProjectId = await _fetchMetricsForProjectIds(
      snap.docs.map((doc) => doc.id),
    );
    final items = snap.docs
        .map(
          (doc) => Project.fromMap(
            doc.id,
            mergeProjectMetricsData(
              projectData: doc.data(),
              metricsData: metricsByProjectId[doc.id],
            ),
          ),
        )
        .toList();
    final actions = await _queue.list(includeExpiredSynced: true);
    final mergedItems = _applyOptimisticProjectList(
      baseItems: items,
      actions: actions,
      workspaceId: workspaceId,
      includePendingCreates: cursor == null,
    );

    return FirestorePage<Project>(
      items: mergedItems,
      hasMore: snap.docs.length == pageSize,
      nextCursor: snap.docs.isEmpty ? cursor : snap.docs.last,
    );
  }

  @override
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
  }) async {
    final firestoreCursor = cursor as DocumentSnapshot<Map<String, dynamic>>?;
    var query = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(firestoreCursor!);
    }

    final snap = await query.get();
    final metricsByProjectId = await _fetchMetricsForProjectIds(
      snap.docs.map((doc) => doc.id),
    );
    final items = snap.docs
        .map(
          (doc) => Project.fromMap(
            doc.id,
            mergeProjectMetricsData(
              projectData: doc.data(),
              metricsData: metricsByProjectId[doc.id],
            ),
          ),
        )
        .toList();
    final actions = await _queue.list(includeExpiredSynced: true);
    final mergedItems = _applyOptimisticProjectList(
      baseItems: items,
      actions: actions,
      workspaceId: workspaceId,
      includePendingCreates: false,
    );

    return FirestorePage<Project>(
      items: mergedItems,
      hasMore: snap.docs.length == pageSize,
      nextCursor: snap.docs.isEmpty ? cursor : snap.docs.last,
    );
  }

  @override
  Future<FirestorePage<Project>> fetchProjectBrowsePage(
    ProjectBrowseQuery request, {
    Object? cursor,
  }) {
    if (request.sort.isFinancial) {
      return _fetchFinancialProjectPage(request, cursor: cursor);
    }
    return _fetchProjectFieldPage(request, cursor: cursor);
  }

  Future<FirestorePage<Project>> _fetchProjectFieldPage(
    ProjectBrowseQuery request, {
    Object? cursor,
  }) async {
    final firestoreCursor = cursor as DocumentSnapshot<Map<String, dynamic>>?;
    Query<Map<String, dynamic>> query = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: request.workspaceId);
    if (!request.includeArchived) {
      query = query.where('isArchived', isEqualTo: false);
    }
    if (request.status != null && request.status!.isNotEmpty) {
      query = query.where('status', isEqualTo: request.status);
    }
    query = switch (request.sort) {
      ProjectBrowseSort.name => query.orderBy('name').orderBy('id'),
      _ => query.orderBy('createdAt', descending: true).orderBy('id'),
    };
    if (cursor != null) {
      query = switch (request.sort) {
        ProjectBrowseSort.name => query.startAt([
          firestoreCursor!.data()?['name'],
          firestoreCursor.data()?['id'] ?? firestoreCursor.id,
        ]),
        _ => query.startAt([
          firestoreCursor!.data()?['createdAt'],
          firestoreCursor.data()?['id'] ?? firestoreCursor.id,
        ]),
      };
    }
    query = query.limit(request.pageSize + (cursor == null ? 0 : 1));

    final snapshot = await query.get();
    final pageDocs = snapshot.docs
        .where(
          (doc) =>
              cursor == null ||
              _isProjectDocAfterCursor(doc, firestoreCursor!, request.sort),
        )
        .take(request.pageSize)
        .toList(growable: false);
    final actions = await _queue.list(includeExpiredSynced: true);
    final metricsByProjectId = await _fetchMetricsForProjectIds(
      pageDocs.map((doc) => doc.id),
    );
    final projects = pageDocs
        .map(
          (doc) => Project.fromMap(
            doc.id,
            mergeProjectMetricsData(
              projectData: doc.data(),
              metricsData: metricsByProjectId[doc.id],
            ),
          ),
        )
        .toList(growable: false);
    final items = _applyOptimisticProjectList(
      baseItems: projects,
      actions: actions,
      workspaceId: request.workspaceId,
      includePendingCreates: cursor == null && !request.includeArchived,
    );

    return FirestorePage<Project>(
      items: items,
      hasMore: cursor == null
          ? snapshot.docs.length == request.pageSize
          : snapshot.docs.length > request.pageSize,
      nextCursor: pageDocs.isEmpty ? cursor : pageDocs.last,
    );
  }

  Future<FirestorePage<Project>> _fetchFinancialProjectPage(
    ProjectBrowseQuery request, {
    Object? cursor,
  }) async {
    final firestoreCursor = cursor as DocumentSnapshot<Map<String, dynamic>>?;
    final metricField = switch (request.sort) {
      ProjectBrowseSort.highestExpense => 'totalExpenses',
      ProjectBrowseSort.highestIncome => 'totalIncome',
      ProjectBrowseSort.highestNet => 'net',
      _ => throw ArgumentError.value(request.sort, 'sort'),
    };
    Query<Map<String, dynamic>> query = _firestore
        .collection('project_metrics')
        .where('workspaceId', isEqualTo: request.workspaceId);
    if (!request.includeArchived) {
      query = query.where('isArchived', isEqualTo: false);
    }
    if (request.status != null && request.status!.isNotEmpty) {
      query = query.where('status', isEqualTo: request.status);
    }
    query = query
        .orderBy(metricField, descending: true)
        .orderBy('projectName')
        .orderBy('projectId');
    if (cursor != null) {
      query = query.startAt([
        firestoreCursor!.data()?[metricField],
        firestoreCursor.data()?['projectName'],
        firestoreCursor.data()?['projectId'],
      ]);
    }
    query = query.limit(request.pageSize + (cursor == null ? 0 : 1));

    final metricSnapshot = await query.get();
    final metricDocs = metricSnapshot.docs
        .where(
          (doc) =>
              cursor == null ||
              _isMetricDocAfterCursor(doc, firestoreCursor!, metricField),
        )
        .take(request.pageSize)
        .toList(growable: false);
    final projectSnapshots = await Future.wait(
      metricDocs.map(
        (metric) => _firestore.collection('projects').doc(metric.id).get(),
      ),
    );
    final projectsById = {
      for (final snapshot in projectSnapshots)
        if (snapshot.exists) snapshot.id: snapshot,
    };
    final orderedProjects = <Project>[];
    for (final metric in metricDocs) {
      final project = projectsById[metric.id];
      if (project == null) continue;
      orderedProjects.add(
        Project.fromMap(
          project.id,
          mergeProjectMetricsData(
            projectData: project.data() ?? const {},
            metricsData: metric.data(),
          ),
        ),
      );
    }
    final actions = await _queue.list(includeExpiredSynced: true);
    final items = _applyOptimisticProjectList(
      baseItems: orderedProjects,
      actions: actions,
      workspaceId: request.workspaceId,
      includePendingCreates: false,
    );

    return FirestorePage<Project>(
      items: items,
      hasMore: cursor == null
          ? metricSnapshot.docs.length == request.pageSize
          : metricSnapshot.docs.length > request.pageSize,
      nextCursor: metricDocs.isEmpty ? cursor : metricDocs.last,
    );
  }

  bool _isProjectDocAfterCursor(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    DocumentSnapshot<Map<String, dynamic>> cursor,
    ProjectBrowseSort sort,
  ) {
    final docData = doc.data();
    final cursorData = cursor.data() ?? const {};
    if (sort == ProjectBrowseSort.name) {
      final nameCompare = '${docData['name'] ?? ''}'.compareTo(
        '${cursorData['name'] ?? ''}',
      );
      if (nameCompare != 0) return nameCompare > 0;
    } else {
      final dateCompare = _compareOrderedValues(
        docData['createdAt'],
        cursorData['createdAt'],
      );
      if (dateCompare != 0) return dateCompare < 0;
    }
    final docId = '${docData['id'] ?? doc.id}';
    final cursorId = '${cursorData['id'] ?? cursor.id}';
    return docId.compareTo(cursorId) > 0;
  }

  bool _isMetricDocAfterCursor(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    DocumentSnapshot<Map<String, dynamic>> cursor,
    String metricField,
  ) {
    final docData = doc.data();
    final cursorData = cursor.data() ?? const {};
    final metricCompare = _compareOrderedValues(
      docData[metricField],
      cursorData[metricField],
    );
    if (metricCompare != 0) return metricCompare < 0;
    final nameCompare = '${docData['projectName'] ?? ''}'.compareTo(
      '${cursorData['projectName'] ?? ''}',
    );
    if (nameCompare != 0) return nameCompare > 0;
    return '${docData['projectId'] ?? doc.id}'.compareTo(
          '${cursorData['projectId'] ?? cursor.id}',
        ) >
        0;
  }

  int _compareOrderedValues(Object? left, Object? right) {
    if (left is Timestamp && right is Timestamp) {
      return left.compareTo(right);
    }
    if (left is DateTime && right is DateTime) {
      return left.compareTo(right);
    }
    if (left is num && right is num) {
      return left.compareTo(right);
    }
    return '$left'.compareTo('$right');
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
  Future<Project?> getProject(String projectId) async {
    final results = await Future.wait([
      _firestore.collection('projects').doc(projectId).get(),
      _firestore.collection('project_metrics').doc(projectId).get(),
    ]);
    final snap = results[0];
    if (!snap.exists) {
      return null;
    }
    final metricsSnap = results[1];
    return Project.fromMap(
      snap.id,
      mergeProjectMetricsData(
        projectData: snap.data() ?? const {},
        metricsData: metricsSnap.exists ? metricsSnap.data() : null,
      ),
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

  Stream<List<Project>> _watchProjectQueryWithMetrics({
    required Query<Map<String, dynamic>> query,
    required String workspaceId,
    required bool includePendingCreates,
    bool excludeArchived = false,
    int? maxResults,
  }) {
    return Stream.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? currentProjects;
      Map<String, Map<String, dynamic>> metricsByProjectId = const {};
      List<OfflineAction> currentActions = const [];
      var metricsGeneration = 0;

      void emit() {
        if (currentProjects == null) {
          return;
        }
        final ranked = currentProjects!.docs
            .map((doc) {
              final merged = mergeProjectMetricsData(
                projectData: doc.data(),
                metricsData: metricsByProjectId[doc.id],
              );
              if (excludeArchived && merged['isArchived'] == true) {
                return null;
              }
              return (
                project: Project.fromMap(doc.id, merged),
                createdAt: merged['createdAt'],
              );
            })
            .whereType<({Project project, Object? createdAt})>()
            .toList();
        ranked.sort(
          (left, right) =>
              _compareOrderedValues(right.createdAt, left.createdAt),
        );
        final limited = maxResults == null ? ranked : ranked.take(maxResults);
        final projects = limited
            .map((entry) => entry.project)
            .toList(growable: false);
        controller.add(
          _applyOptimisticProjectList(
            baseItems: projects,
            actions: currentActions,
            workspaceId: workspaceId,
            includePendingCreates: includePendingCreates,
          ),
        );
      }

      Future<void> refreshMetrics() async {
        final snapshot = currentProjects;
        if (snapshot == null) {
          return;
        }
        final generation = ++metricsGeneration;
        try {
          final fetched = await _fetchMetricsForProjectIds(
            snapshot.docs.map((doc) => doc.id),
          );
          if (generation != metricsGeneration) {
            return;
          }
          metricsByProjectId = fetched;
          emit();
        } catch (error, stackTrace) {
          if (generation != metricsGeneration) {
            return;
          }
          controller.addError(error, stackTrace);
        }
      }

      unawaited(() async {
        try {
          currentProjects = await query.get();
          currentActions = await _queue.list(includeExpiredSynced: true);
          emit();
          unawaited(refreshMetrics());
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        }
      }());

      final queueSub = _queue.watch(includeExpiredSynced: true).listen((
        actions,
      ) {
        currentActions = actions;
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        metricsGeneration += 1;
        await queueSub.cancel();
      };
    });
  }

  Future<Map<String, Map<String, dynamic>>> _fetchMetricsForProjectIds(
    Iterable<String> projectIds,
  ) async {
    final ids = projectIds.toSet();
    if (ids.isEmpty) {
      return const {};
    }
    final snaps = await Future.wait(
      ids.map((id) => _firestore.collection('project_metrics').doc(id).get()),
    );
    return {
      for (final snap in snaps)
        if (snap.exists) snap.id: snap.data() ?? const {},
    };
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
  if (BackendConfig.fromEnvironment.useSelfHostedBackend) {
    return LocalProjectRepository(
      ref.watch(firestoreProvider),
      ref.watch(workspaceMutationServiceProvider),
      ref.watch(offlineActionQueueProvider),
      ref.watch(localDatabaseProvider),
    );
  }
  return FirebaseProjectRepository(
    ref.watch(firestoreProvider),
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
  );
});
