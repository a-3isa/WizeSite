import 'package:buildtrack_app/core/pagination/local_page.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/json_safe.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

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

final entityRepositoryProvider = Provider<EntityRepository>((ref) {
  return LocalEntityRepository(
    ref.watch(localDatabaseProvider),
    ref.watch(workspaceMutationServiceProvider),
  );
});
