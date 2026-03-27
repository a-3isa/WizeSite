import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class WorkerRepository {
  Stream<List<WorkerProfile>> watchWorkers(String workspaceId);
  Future<FirestorePage<WorkerProfile>> fetchWorkersPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  });
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

  Future<MutationResult> createEntry({
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

  Future<MutationResult> archiveEntry(String entryId);
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
  Future<FirestorePage<WorkerProfile>> fetchWorkersPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    var query = _firestore
        .collection('workers')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }

    final snap = await query.get();
    final items = snap.docs
        .map((doc) => WorkerProfile.fromMap(doc.id, doc.data()))
        .toList();

    return FirestorePage<WorkerProfile>(
      items: items,
      hasMore: snap.docs.length == pageSize,
      nextCursor: snap.docs.isEmpty ? cursor : snap.docs.last,
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
  FirebaseWorkerEntryRepository(
    this._firestore,
    this._mutationService,
    this._queue,
  );

  final FirebaseFirestore _firestore;
  final WorkspaceMutationService _mutationService;
  final OfflineActionQueue _queue;

  @override
  Stream<List<WorkerEntryRecord>> watchEntriesByWorker({
    required String workspaceId,
    required String workerId,
  }) {
    final baseStream = _firestore
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
    final queueStream = _queue.watch();
    return Stream.multi((controller) {
      List<WorkerEntryRecord> current = const [];
      List<OfflineAction> actions = const [];

      void emit() {
        controller.add(
          _applyPendingEntries(
            baseItems: current,
            actions: actions,
            workspaceId: workspaceId,
            workerId: workerId,
          ),
        );
      }

      final baseSub = baseStream.listen(
        (items) {
          current = items;
          emit();
        },
        onError: controller.addError,
      );
      final queueSub = queueStream.listen(
        (value) {
          actions = value;
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
  Future<MutationResult> createEntry({
    required String workspaceId,
    required String userId,
    required String workerId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
  }) async {
    return _mutationService.createWorkerEntry(
      workspaceId: workspaceId,
      workerId: workerId,
      projectId: projectId,
      daysWorked: daysWorked,
      dailyWage: dailyWage,
      date: date,
      notes: notes,
    );
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
  Future<MutationResult> archiveEntry(String entryId) async {
    final entry = await getEntry(entryId);
    if (entry == null) {
      return const MutationResult();
    }
    return _mutationService.archiveWorkerEntry(
      workspaceId: entry.workspaceId,
      entryId: entryId,
    );
  }

  List<WorkerEntryRecord> _applyPendingEntries({
    required List<WorkerEntryRecord> baseItems,
    required List<OfflineAction> actions,
    required String workspaceId,
    required String workerId,
  }) {
    final items = List<WorkerEntryRecord>.from(baseItems);
    final archivedIds = <String>{};

    for (final action in actions) {
      final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
      if (payloadWorkspaceId != workspaceId) {
        continue;
      }
      if (action.type == OfflineActionTypes.archiveWorkerEntry) {
        final entryId = '${action.payload['entryId'] ?? ''}';
        if (entryId.isNotEmpty) {
          archivedIds.add(entryId);
        }
      }
    }

    if (archivedIds.isNotEmpty) {
      items.removeWhere((item) => archivedIds.contains(item.id));
    }

    for (final action in actions) {
      if (action.type != OfflineActionTypes.createWorkerEntry) {
        continue;
      }
      final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
      final payloadWorkerId = '${action.payload['workerId'] ?? ''}';
      if (payloadWorkspaceId != workspaceId || payloadWorkerId != workerId) {
        continue;
      }
      items.insert(0, _entryFromCreateAction(action));
    }

    final deduped = <String, WorkerEntryRecord>{};
    for (final item in items) {
      deduped[item.id] = item;
    }
    final result = deduped.values.toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  WorkerEntryRecord _entryFromCreateAction(OfflineAction action) {
    final payload = action.payload;
    final parsedDate = DateTime.tryParse('${payload['date'] ?? ''}');
    final daysWorked = (payload['daysWorked'] as num?)?.toDouble() ?? 0;
    final dailyWage = (payload['dailyWage'] as num?)?.toDouble() ?? 0;
    return WorkerEntryRecord(
      id: 'pending_${action.id}',
      workspaceId: '${payload['workspaceId'] ?? ''}',
      workerId: '${payload['workerId'] ?? ''}',
      projectId: '${payload['projectId'] ?? ''}',
      daysWorked: daysWorked,
      dailyWage: dailyWage,
      totalCost: daysWorked * dailyWage,
      date: parsedDate ?? action.createdAt,
      notes: '${payload['notes'] ?? ''}',
      isArchived: false,
    );
  }
}

final workerRepositoryProvider = Provider<WorkerRepository>((ref) {
  return FirebaseWorkerRepository(ref.watch(firestoreProvider));
});

final workerEntryRepositoryProvider = Provider<WorkerEntryRepository>((ref) {
  return FirebaseWorkerEntryRepository(
    ref.watch(firestoreProvider),
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
  );
});
