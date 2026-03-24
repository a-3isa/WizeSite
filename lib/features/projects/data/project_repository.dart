import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ProjectRepository {
  Stream<List<Project>> watchProjects(String workspaceId);
  Stream<List<Project>> watchAllProjects(String workspaceId);
  Stream<List<Project>> watchArchivedProjects(String workspaceId);
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
  Future<void> unarchiveProject(String projectId);
  Future<void> deleteProject(String projectId);
}

class FirebaseProjectRepository implements ProjectRepository {
  FirebaseProjectRepository(this._firestore);

  final FirebaseFirestore _firestore;

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
  Stream<List<Project>> watchAllProjects(String workspaceId) {
    return _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Project.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) {
    return _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: true)
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
    final ref = _firestore.collection('projects').doc();
    await ref.set({
      'id': ref.id,
      'workspaceId': workspaceId,
      'ownerId': userId,
      'name': name,
      'clientName': clientName,
      'contractValue': contractValue,
      'startDate': Timestamp.fromDate(startDate),
      'expectedEndDate':
          expectedEndDate == null ? null : Timestamp.fromDate(expectedEndDate),
      'location': location ?? '',
      'description': description ?? '',
      'budgetLimit': budgetLimit,
      'completionPercentage': completionPercentage,
      'status': 'active',
      'totalExpenses': 0,
      'totalLaborCost': 0,
      'totalPayments': 0,
      'netProfit': 0,
      'expectedFinalCost': 0,
      'remainingBalance': contractValue,
      'riskLevel': 'low',
      'healthStatus': 'healthy',
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isArchived': false,
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

  @override
  Future<void> unarchiveProject(String projectId) async {
    await _firestore.collection('projects').doc(projectId).update({
      'isArchived': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteProject(String projectId) async {
    await _firestore.collection('projects').doc(projectId).delete();
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return FirebaseProjectRepository(ref.watch(firestoreProvider));
});
