import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/pagination/local_page.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

part 'local_entity_repository.dart';

/// Ordering options for an exact-type entity directory.
enum EntityDirectorySort {
  /// Most-recently used first (by `lastUsedAt` timestamp).
  recent,

  /// Alphabetical by normalized name.
  name,

  /// By document id (stable, total order).
  id,
}

abstract interface class EntityRepository {
  Stream<List<AppEntity>> watchEntities(
    String workspaceId, {
    String? type,
    int limit,
  });

  /// Cursor-paged directory of entities of an exact [type], ordered by [sort].
  Future<FirestorePage<AppEntity>> fetchEntityDirectoryPage(
    String workspaceId, {
    required String type,
    EntityDirectorySort sort,
    Object? cursor,
    int pageSize,
  });

  Future<List<AppEntity>> searchEntities(
    String workspaceId,
    String query, {
    String? type,
    int limit,
  });

  Future<AppEntity?> getEntityById(String entityId);

  Future<AppEntity?> getEntityByName(
    String workspaceId,
    String name, {
    String? type,
  });

  Future<AppEntity?> ensureEntity({
    required String workspaceId,
    required String name,
    String? type,
  });

  Future<AppEntity> createEntity({
    required String workspaceId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  });

  Future<AppEntity> updateEntity({
    required String entityId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  });

  Future<void> deleteEntity(String entityId);

  Future<void> saveAttachments({
    required String entityId,
    required List<Map<String, dynamic>> attachments,
  });
}

class FirebaseEntityRepository implements EntityRepository {
  FirebaseEntityRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static String normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Query<Map<String, dynamic>> _baseQuery(String workspaceId, {String? type}) {
    var query = _firestore
        .collection('entities')
        .where('workspaceId', isEqualTo: workspaceId);
    if (type != null && type.isNotEmpty) {
      query = query.where('type', isEqualTo: type);
    }
    return query.orderBy('lastUsedAt', descending: true);
  }

  @override
  Stream<List<AppEntity>> watchEntities(
    String workspaceId, {
    String? type,
    int limit = 20,
  }) {
    return _baseQuery(workspaceId, type: type)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => AppEntity.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<FirestorePage<AppEntity>> fetchEntityDirectoryPage(
    String workspaceId, {
    required String type,
    EntityDirectorySort sort = EntityDirectorySort.recent,
    Object? cursor,
    int pageSize = 20,
  }) async {
    final firestoreCursor = cursor as DocumentSnapshot<Map<String, dynamic>>?;
    Query<Map<String, dynamic>> query = _firestore
        .collection('entities')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('type', isEqualTo: type);

    query = switch (sort) {
      EntityDirectorySort.recent =>
        query
            .orderBy('lastUsedAt', descending: true)
            .orderBy('normalizedName')
            .orderBy('id'),
      EntityDirectorySort.name => query.orderBy('normalizedName').orderBy('id'),
      EntityDirectorySort.id => query.orderBy('id'),
    };

    if (cursor != null) {
      query = switch (sort) {
        EntityDirectorySort.recent => query.startAfter([
          firestoreCursor!.data()?['lastUsedAt'],
          firestoreCursor.data()?['normalizedName'],
          firestoreCursor.data()?['id'] ?? firestoreCursor.id,
        ]),
        EntityDirectorySort.name => query.startAfter([
          firestoreCursor!.data()?['normalizedName'],
          firestoreCursor.data()?['id'] ?? firestoreCursor.id,
        ]),
        EntityDirectorySort.id => query.startAfter([
          firestoreCursor!.data()?['id'] ?? firestoreCursor.id,
        ]),
      };
    }

    query = query.limit(pageSize);

    final snap = await query.get();
    final items = snap.docs
        .map((doc) => AppEntity.fromMap(doc.id, doc.data()))
        .toList(growable: false);

    return FirestorePage<AppEntity>(
      items: items,
      hasMore: snap.docs.length == pageSize,
      nextCursor: snap.docs.isEmpty ? cursor : snap.docs.last,
    );
  }

  @override
  Future<List<AppEntity>> searchEntities(
    String workspaceId,
    String query, {
    String? type,
    int limit = 20,
  }) async {
    final normalized = normalizeName(query);
    var queryRef = _firestore
        .collection('entities')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('normalizedName', isGreaterThanOrEqualTo: normalized)
        .where('normalizedName', isLessThanOrEqualTo: '$normalized\uf8ff');
    if (type != null && type.isNotEmpty) {
      queryRef = queryRef.where('type', isEqualTo: type);
    }
    final snap = await queryRef.get();
    final entities =
        snap.docs.map((doc) => AppEntity.fromMap(doc.id, doc.data())).toList()
          ..sort(_compareRecentFirst);
    return entities.take(limit).toList(growable: false);
  }

  @override
  Future<AppEntity?> getEntityById(String entityId) async {
    final snap = await _firestore.collection('entities').doc(entityId).get();
    if (!snap.exists) {
      return null;
    }
    return AppEntity.fromMap(snap.id, snap.data() ?? const {});
  }

  @override
  Future<AppEntity?> getEntityByName(
    String workspaceId,
    String name, {
    String? type,
  }) async {
    final normalized = normalizeName(name);
    var queryRef = _firestore
        .collection('entities')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('normalizedName', isEqualTo: normalized);
    if (type != null && type.isNotEmpty) {
      queryRef = queryRef.where('type', isEqualTo: type);
    }
    queryRef = queryRef.limit(1);
    final snap = await queryRef.get();
    if (snap.docs.isEmpty) {
      return null;
    }
    return AppEntity.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  @override
  Future<AppEntity?> ensureEntity({
    required String workspaceId,
    required String name,
    String? type,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final existing = await getEntityByName(workspaceId, trimmed, type: type);
      if (existing != null) {
        await _firestore.collection('entities').doc(existing.id).set({
          'lastUsedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        final refreshed = await getEntityById(existing.id);
        return refreshed ?? existing;
      }
      final normalized = normalizeName(trimmed);
      final ref = await _firestore.collection('entities').add({
        'workspaceId': workspaceId,
        'name': trimmed,
        'normalizedName': normalized,
        'type': type ?? 'supplier',
        'createdAt': FieldValue.serverTimestamp(),
        'lastUsedAt': FieldValue.serverTimestamp(),
        'attachments': const <Map<String, dynamic>>[],
      });
      await ref.set({'id': ref.id}, SetOptions(merge: true));
      final createdSnap = await ref.get();
      if (!createdSnap.exists) {
        return null;
      }
      return AppEntity.fromMap(ref.id, createdSnap.data() ?? const {});
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AppEntity> createEntity({
    required String workspaceId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Entity name cannot be empty');
    }
    final trimmedRateUnit = rateUnit?.trim();
    final trimmedPhoneNumber = phoneNumber?.trim();
    final trimmedNotes = notes?.trim();
    final ref = _firestore.collection('entities').doc();
    final payload = <String, dynamic>{
      'id': ref.id,
      'workspaceId': workspaceId,
      'name': trimmed,
      'normalizedName': normalizeName(trimmed),
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUsedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'attachments': const <Map<String, dynamic>>[],
    };
    if (defaultRate != null) {
      payload['defaultRate'] = defaultRate;
    }
    if (trimmedRateUnit?.isNotEmpty == true) {
      payload['rateUnit'] = trimmedRateUnit;
    }
    if (trimmedPhoneNumber?.isNotEmpty == true) {
      payload['phoneNumber'] = trimmedPhoneNumber;
    }
    if (trimmedNotes?.isNotEmpty == true) {
      payload['notes'] = trimmedNotes;
    }
    await ref.set(payload);
    final created = await ref.get();
    return AppEntity.fromMap(ref.id, created.data() ?? const {});
  }

  @override
  Future<AppEntity> updateEntity({
    required String entityId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Entity name cannot be empty');
    }
    final ref = _firestore.collection('entities').doc(entityId);
    await ref.set({
      'name': trimmed,
      'normalizedName': normalizeName(trimmed),
      'type': type,
      'defaultRate': defaultRate ?? FieldValue.delete(),
      'rateUnit': rateUnit?.trim().isNotEmpty == true
          ? rateUnit!.trim()
          : FieldValue.delete(),
      'phoneNumber': phoneNumber?.trim().isNotEmpty == true
          ? phoneNumber!.trim()
          : FieldValue.delete(),
      'notes': notes?.trim().isNotEmpty == true
          ? notes!.trim()
          : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastUsedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final updated = await ref.get();
    return AppEntity.fromMap(entityId, updated.data() ?? const {});
  }

  @override
  Future<void> deleteEntity(String entityId) {
    return _firestore.collection('entities').doc(entityId).delete();
  }

  @override
  Future<void> saveAttachments({
    required String entityId,
    required List<Map<String, dynamic>> attachments,
  }) {
    return _firestore.collection('entities').doc(entityId).set({
      'attachments': attachments,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static int _compareRecentFirst(AppEntity left, AppEntity right) {
    final leftDate = left.lastUsedAt ?? left.createdAt;
    final rightDate = right.lastUsedAt ?? right.createdAt;
    final byDate = rightDate.compareTo(leftDate);
    if (byDate != 0) {
      return byDate;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  }
}

final entityRepositoryProvider = Provider<EntityRepository>((ref) {
  if (BackendConfig.fromEnvironment.useSelfHostedBackend) {
    return LocalEntityRepository(
      ref.watch(firestoreProvider),
      ref.watch(localDatabaseProvider),
    );
  }
  return FirebaseEntityRepository(ref.watch(firestoreProvider));
});
