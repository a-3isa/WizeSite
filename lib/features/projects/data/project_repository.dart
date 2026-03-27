import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
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
    final baseStream = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Project.fromMap(doc.id, doc.data()))
              .toList(),
        );
    return _watchProjectsWithOptimistic(
      baseStream: baseStream,
      workspaceId: workspaceId,
      includePendingCreates: true,
    );
  }

  @override
  Stream<List<Project>> watchAllProjects(String workspaceId) {
    final baseStream = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Project.fromMap(doc.id, doc.data()))
              .toList(),
        );
    return _watchProjectsWithOptimistic(
      baseStream: baseStream,
      workspaceId: workspaceId,
      includePendingCreates: true,
    );
  }

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) {
    final baseStream = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Project.fromMap(doc.id, doc.data()))
              .toList(),
        );
    return _watchProjectsWithOptimistic(
      baseStream: baseStream,
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

    final baseStream = _firestore.collection('projects').doc(projectId).snapshots().map((
      snap,
    ) {
      if (!snap.exists) {
        return null;
      }
      return Project.fromMap(snap.id, snap.data() ?? const {});
    });

    final queueStream = _queue.watch();
    return Stream.multi((controller) {
      Project? currentProject;
      List<OfflineAction> currentActions = const [];

      void emit() {
        final baseProject = currentProject;
        if (baseProject == null) {
          controller.add(null);
          return;
        }
        controller.add(_applyPendingDeltas(baseProject, currentActions));
      }

      final projectSub = baseStream.listen(
        (project) {
          currentProject = project;
          emit();
        },
        onError: controller.addError,
      );
      final queueSub = queueStream.listen(
        (actions) {
          currentActions = actions;
          emit();
        },
        onError: controller.addError,
      );

      controller.onCancel = () async {
        await projectSub.cancel();
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
    final items = snap.docs
        .map((doc) => Project.fromMap(doc.id, doc.data()))
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
    final items = snap.docs
        .map((doc) => Project.fromMap(doc.id, doc.data()))
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
    final snap = await _firestore.collection('projects').doc(projectId).get();
    if (!snap.exists) {
      return null;
    }
    return Project.fromMap(snap.id, snap.data() ?? const {});
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
    await _firestore.collection('projects').doc(projectId).update({
      'name': name,
      'clientName': clientName,
      'contractValue': contractValue,
      'startDate': Timestamp.fromDate(startDate),
      'expectedEndDate': expectedEndDate == null
          ? null
          : Timestamp.fromDate(expectedEndDate),
      'location': location ?? '',
      'description': description ?? '',
      'budgetLimit': budgetLimit,
      'completionPercentage': completionPercentage ?? 0,
      'status': status ?? 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> archiveProject(String projectId) async {
    await _firestore.collection('projects').doc(projectId).update({
      'isArchived': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  Stream<List<Project>> _watchProjectsWithOptimistic({
    required Stream<List<Project>> baseStream,
    required String workspaceId,
    required bool includePendingCreates,
  }) {
    final queueStream = _queue.watch();
    return Stream.multi((controller) {
      List<Project> currentProjects = const [];
      List<OfflineAction> currentActions = const [];

      void emit() {
        controller.add(
          _applyOptimisticProjectList(
            baseItems: currentProjects,
            actions: currentActions,
            workspaceId: workspaceId,
            includePendingCreates: includePendingCreates,
          ),
        );
      }

      final baseSub = baseStream.listen(
        (projects) {
          currentProjects = projects;
          emit();
        },
        onError: controller.addError,
      );
      final queueSub = queueStream.listen(
        (actions) {
          currentActions = actions;
          emit();
        },
        onError: controller.addError,
      );

      controller.onCancel = () async {
        await baseSub.cancel();
        await queueSub.cancel();
      };
    });
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

    if (includePendingCreates) {
      final pendingProjects = <Project>[];
      for (final action in actions) {
        if (action.type != OfflineActionTypes.createProject) {
          continue;
        }
        if ('${action.payload['workspaceId'] ?? ''}' != workspaceId) {
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
        case OfflineActionTypes.createWorkerEntry:
          final daysWorked = (action.payload['daysWorked'] as num?) ?? 0;
          final dailyWage = (action.payload['dailyWage'] as num?) ?? 0;
          pendingExpenses += daysWorked * dailyWage;
          break;
        case OfflineActionTypes.createPayment:
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
