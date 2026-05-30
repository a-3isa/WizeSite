import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class EntityRepository {
  Stream<List<AppEntity>> watchEntities(
    String workspaceId, {
    String? type,
    int limit,
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
    var query = _firestore.collection('entities').where(
          'workspaceId',
          isEqualTo: workspaceId,
        );
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
        .map((snap) => snap.docs
            .map((doc) => AppEntity.fromMap(doc.id, doc.data()))
            .toList());
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
    final entities = snap.docs
        .map((doc) => AppEntity.fromMap(doc.id, doc.data()))
        .toList()
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
        'attachments': const [],
      });
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
  return FirebaseEntityRepository(ref.watch(firestoreProvider));
});
