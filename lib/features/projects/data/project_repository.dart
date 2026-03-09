import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ProjectRepository {
  Stream<List<Project>> watchProjects(String workspaceId);
  Future<void> createProject({
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
}

class FirebaseProjectRepository implements ProjectRepository {
  FirebaseProjectRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<List<Project>> watchProjects(String workspaceId) {
    return _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Project.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<void> createProject({
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
    final callable = _functions.httpsCallable('createProjectWithQuota');
    await callable.call<Map<String, dynamic>>({
      'workspaceId': workspaceId,
      'userId': userId,
      'name': name,
      'clientName': clientName,
      'contractValue': contractValue,
      'startDate': startDate.toIso8601String(),
      'expectedEndDate': expectedEndDate?.toIso8601String(),
      'location': location,
      'description': description,
      'budgetLimit': budgetLimit,
      'completionPercentage': completionPercentage,
    });
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
}

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return FirebaseProjectRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
  );
});
