import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/data/project_metrics_merger.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ProjectRepository {
  Stream<List<Project>> watchProjects(String workspaceId);
  Stream<List<Project>> watchAllProjects(String workspaceId);
  Stream<List<Project>> watchArchivedProjects(String workspaceId);
  Stream<Project?> watchProject(String projectId);
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  });
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  });
  Future<MutationResult> createProject({
    required String workspaceId,
    required String userId,
    required String name,
    required String clientName,
    required double contractValue,
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
    required double contractValue,
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
}

class FirebaseProjectRepository implements ProjectRepository {
  FirebaseProjectRepository(
    this._firestore,
    this._mutationService,
    this._queue,
  );

  final FirebaseFirestore _firestore;
  final WorkspaceMutationService _mutationService;
  final OfflineActionQueue _queue;

  @override
  Stream<List<Project>> watchProjects(String workspaceId) {
    final query = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false);
    return _watchProjectQueryWithMetrics(
      query: query,
      workspaceId: workspaceId,
      includePendingCreates: true,
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
      return _queue.watch().map((actions) {
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
    final queueStream = _queue.watch();
    return Stream.multi((controller) {
      DocumentSnapshot<Map<String, dynamic>>? currentProjectSnap;
      Map<String, dynamic>? currentMetrics;
      List<OfflineAction> currentActions = const [];

      void emit() {
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

      final projectSub = projectStream.listen((snapshot) {
        currentProjectSnap = snapshot;
        emit();
      }, onError: controller.addError);
      final metricsSub = metricsStream.listen((snapshot) {
        currentMetrics = snapshot.exists ? snapshot.data() : null;
        emit();
      }, onError: controller.addError);
      final queueSub = queueStream.listen((actions) {
        currentActions = actions;
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await projectSub.cancel();
        await metricsSub.cancel();
        await queueSub.cancel();
      };
    });
  }

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    var query = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
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
    final actions = await _queue.list();
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
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    var query = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
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
    final actions = await _queue.list();
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
  Future<MutationResult> createProject({
    required String workspaceId,
    required String userId,
    required String name,
    required String clientName,
    required double contractValue,
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
    required double contractValue,
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
    await _firestore.collection('projects').doc(projectId).update({
      'isArchived': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
  }) {
    final projectsStream = query.snapshots();
    final metricsStream = _firestore
        .collection('project_metrics')
        .where('workspaceId', isEqualTo: workspaceId)
        .snapshots();
    final queueStream = _queue.watch();
    return Stream.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? currentProjects;
      QuerySnapshot<Map<String, dynamic>>? currentMetrics;
      List<OfflineAction> currentActions = const [];

      void emit() {
        final metricsByProjectId = {
          for (final doc in currentMetrics?.docs ?? const [])
            doc.id: doc.data(),
        };
        final projects = (currentProjects?.docs ?? const [])
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
        controller.add(
          _applyOptimisticProjectList(
            baseItems: projects,
            actions: currentActions,
            workspaceId: workspaceId,
            includePendingCreates: includePendingCreates,
          ),
        );
      }

      final projectSub = projectsStream.listen((snapshot) {
        currentProjects = snapshot;
        emit();
      }, onError: controller.addError);
      final metricsSub = metricsStream.listen((snapshot) {
        currentMetrics = snapshot;
        emit();
      }, onError: controller.addError);
      final queueSub = queueStream.listen((actions) {
        currentActions = actions;
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await projectSub.cancel();
        await metricsSub.cancel();
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
        contractValue:
            (action.payload['contractValue'] as num?)?.toDouble() ??
            current.contractValue,
        status: '${action.payload['status'] ?? current.status}',
        completionPercentage:
            (action.payload['completionPercentage'] as num?)?.toDouble() ??
            current.completionPercentage,
        totalExpenses: current.totalExpenses,
        totalPayments: current.totalPayments,
        netProfit: current.netProfit,
        isArchived: current.isArchived,
        clientMutationId: current.clientMutationId,
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
    num pendingExpenses = 0;
    num pendingIncome = 0;

    for (final action in actions) {
      final payloadProjectId = '${action.payload['projectId'] ?? ''}';
      if (payloadProjectId != project.id) {
        continue;
      }
      switch (action.type) {
        case OfflineActionTypes.createExpense:
          pendingExpenses += (action.payload['amount'] as num?) ?? 0;
          break;
        case OfflineActionTypes.updateExpense:
          pendingExpenses -= (action.payload['previousAmount'] as num?) ?? 0;
          pendingExpenses += (action.payload['amount'] as num?) ?? 0;
          break;
        case OfflineActionTypes.createWorkerEntry:
          final daysWorked = (action.payload['daysWorked'] as num?) ?? 0;
          final dailyWage = (action.payload['dailyWage'] as num?) ?? 0;
          pendingExpenses += daysWorked * dailyWage;
          break;
        case OfflineActionTypes.createPayment:
          pendingIncome += (action.payload['amount'] as num?) ?? 0;
          break;
        case OfflineActionTypes.updatePayment:
          pendingIncome -= (action.payload['previousAmount'] as num?) ?? 0;
          pendingIncome += (action.payload['amount'] as num?) ?? 0;
          break;
        default:
          break;
      }
    }

    if (pendingExpenses == 0 && pendingIncome == 0) {
      return project;
    }

    final totalExpenses = project.totalExpenses + pendingExpenses.toDouble();
    final totalPayments = project.totalPayments + pendingIncome.toDouble();
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
    );
  }

  Project _projectFromCreateAction(OfflineAction action) {
    return Project(
      id: 'pending_${action.id}',
      workspaceId: '${action.payload['workspaceId'] ?? ''}',
      name: '${action.payload['name'] ?? ''}',
      clientName: '${action.payload['clientName'] ?? ''}',
      contractValue: (action.payload['contractValue'] as num?)?.toDouble() ?? 0,
      status: 'active',
      completionPercentage:
          (action.payload['completionPercentage'] as num?)?.toDouble() ?? 0,
      totalExpenses: 0,
      totalPayments: 0,
      netProfit: 0,
      isArchived: false,
      clientMutationId: '${action.payload['clientMutationId'] ?? action.id}',
    );
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return FirebaseProjectRepository(
    ref.watch(firestoreProvider),
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
  );
});
