import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class WorkerRepository {
  Stream<List<WorkerProfile>> watchWorkers(String workspaceId);
  Future<WorkerProfile?> getWorker(String workerId);
  Future<void> createWorker({
    required String workspaceId,
    required String userId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    String? workerType,
    String? notes,
  });

  Future<void> updateWorker({
    required String workerId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    String? workerType,
    String? notes,
  });

  Future<void> archiveWorker(String workerId);
}

abstract interface class WorkerEntryRepository {
  Stream<List<WorkerEntryRecord>> watchEntriesByWorker({
    required String workspaceId,
    required String workerId,
  });

  Future<WorkerEntryRecord?> getEntry(String entryId);

  Future<void> createEntry({
    required String workspaceId,
    required String userId,
    required String workerId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
  });

  Future<void> updateEntry({
    required String entryId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
  });

  Future<void> archiveEntry(String entryId);
}

class FirebaseWorkerRepository implements WorkerRepository {
  FirebaseWorkerRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<WorkerProfile>> watchWorkers(String workspaceId) {
    return _firestore
        .collection('workers')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => WorkerProfile.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<WorkerProfile?> getWorker(String workerId) async {
    final snap = await _firestore.collection('workers').doc(workerId).get();
    if (!snap.exists) {
      return null;
    }
    return WorkerProfile.fromMap(snap.id, snap.data() ?? const {});
  }

  @override
  Future<void> createWorker({
    required String workspaceId,
    required String userId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    String? workerType,
    String? notes,
  }) async {
    await _firestore.collection('workers').add({
      'workspaceId': workspaceId,
      'name': name,
      'phoneNumber': phoneNumber,
      'dailyWage': dailyWage,
      'workerType': workerType ?? '',
      'notes': notes ?? '',
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isArchived': false,
    });
  }

  @override
  Future<void> updateWorker({
    required String workerId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    String? workerType,
    String? notes,
  }) async {
    await _firestore.collection('workers').doc(workerId).update({
      'name': name,
      'phoneNumber': phoneNumber,
      'dailyWage': dailyWage,
      'workerType': workerType ?? '',
      'notes': notes ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> archiveWorker(String workerId) async {
    await _firestore.collection('workers').doc(workerId).update({
      'isArchived': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class FirebaseWorkerEntryRepository implements WorkerEntryRepository {
  FirebaseWorkerEntryRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<List<WorkerEntryRecord>> watchEntriesByWorker({
    required String workspaceId,
    required String workerId,
  }) {
    return _firestore
        .collection('worker_entries')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('workerId', isEqualTo: workerId)
        .where('isArchived', isEqualTo: false)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => WorkerEntryRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<WorkerEntryRecord?> getEntry(String entryId) async {
    final snap = await _firestore
        .collection('worker_entries')
        .doc(entryId)
        .get();
    if (!snap.exists) {
      return null;
    }
    return WorkerEntryRecord.fromMap(snap.id, snap.data() ?? const {});
  }

  @override
  Future<void> createEntry({
    required String workspaceId,
    required String userId,
    required String workerId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
  }) async {
    await _functions.httpsCallable('createWorkerEntryWithQuota').call({
      'workspaceId': workspaceId,
      'userId': userId,
      'workerId': workerId,
      'projectId': projectId,
      'daysWorked': daysWorked,
      'dailyWage': dailyWage,
      'date': date.toIso8601String(),
      'notes': notes ?? '',
    });
  }

  @override
  Future<void> updateEntry({
    required String entryId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
  }) async {
    await _firestore.collection('worker_entries').doc(entryId).update({
      'projectId': projectId,
      'daysWorked': daysWorked,
      'dailyWage': dailyWage,
      'totalCost': daysWorked * dailyWage,
      'date': Timestamp.fromDate(date),
      'notes': notes ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> archiveEntry(String entryId) async {
    await _firestore.collection('worker_entries').doc(entryId).update({
      'isArchived': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

final workerRepositoryProvider = Provider<WorkerRepository>((ref) {
  return FirebaseWorkerRepository(ref.watch(firestoreProvider));
});

final workerEntryRepositoryProvider = Provider<WorkerEntryRepository>((ref) {
  return FirebaseWorkerEntryRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
  );
});
