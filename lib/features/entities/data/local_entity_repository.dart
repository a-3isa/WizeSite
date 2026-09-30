part of 'entity_repository.dart';

/// Entity reads from the local PowerSync replica (spec 004, tasks.md T046).
///
/// Mirrors Firestore semantics exactly, including one subtlety: ordering by a
/// field excludes documents that lack it, so the `lastUsedAt` / `normalizedName`
/// orderings filter `IS NOT NULL`.
///
/// Writes (T082) are queued for the contact RPCs when [WorkspaceMutationService]
/// is given, so they work offline; the new or changed contact is returned at
/// once and reaches the lists when it syncs. Without it (tests) the inherited
/// Firestore writes remain.
class LocalEntityRepository extends FirebaseEntityRepository {
  LocalEntityRepository(
    super.firestore,
    this._db, {
    WorkspaceMutationService? mutations,
  }) : _mutations = mutations;

  final Future<PowerSyncDatabase> _db;
  final WorkspaceMutationService? _mutations;

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// The payload `upsertEntity` expects; the server sets every field from it.
  static Map<String, dynamic> _upsertPayload(AppEntity entity) => {
    'id': entity.id,
    'workspaceId': entity.workspaceId,
    'name': entity.name,
    'type': entity.type,
    'defaultRate': ?entity.defaultRate,
    if (entity.rateUnit.isNotEmpty) 'rateUnit': entity.rateUnit,
    if (entity.phoneNumber.isNotEmpty) 'phoneNumber': entity.phoneNumber,
    if (entity.notes.isNotEmpty) 'notes': entity.notes,
    'attachments': [
      for (final attachment in entity.attachments) attachment.toMap(),
    ],
  };

  Future<AppEntity> _existing(String entityId) async {
    final entity = await getEntityById(entityId);
    if (entity == null) {
      throw ArgumentError.value(entityId, 'entityId', 'Entity not found');
    }
    return entity;
  }

  @override
  Future<AppEntity?> ensureEntity({
    required String workspaceId,
    required String name,
    String? type,
  }) async {
    final mutations = _mutations;
    if (mutations == null) {
      return super.ensureEntity(
        workspaceId: workspaceId,
        name: name,
        type: type,
      );
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final existing = await getEntityByName(workspaceId, trimmed, type: type);
    if (existing != null) {
      await mutations.touchEntityLastUsed(
        workspaceId: workspaceId,
        entityId: existing.id,
      );
      return existing;
    }
    return createEntity(
      workspaceId: workspaceId,
      name: trimmed,
      type: type ?? 'supplier',
    );
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
    final mutations = _mutations;
    if (mutations == null) {
      return super.createEntity(
        workspaceId: workspaceId,
        name: name,
        type: type,
        defaultRate: defaultRate,
        rateUnit: rateUnit,
        phoneNumber: phoneNumber,
        notes: notes,
      );
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Entity name cannot be empty');
    }
    final now = DateTime.now().toUtc();
    final entity = AppEntity(
      id: const Uuid().v4(),
      workspaceId: workspaceId,
      name: trimmed,
      normalizedName: FirebaseEntityRepository.normalizeName(trimmed),
      type: type,
      createdAt: now,
      lastUsedAt: now,
      defaultRate: defaultRate,
      rateUnit: _trimmedOrNull(rateUnit) ?? '',
      phoneNumber: _trimmedOrNull(phoneNumber) ?? '',
      notes: _trimmedOrNull(notes) ?? '',
    );
    await mutations.upsertEntity(_upsertPayload(entity));
    return entity;
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
    final mutations = _mutations;
    if (mutations == null) {
      return super.updateEntity(
        entityId: entityId,
        name: name,
        type: type,
        defaultRate: defaultRate,
        rateUnit: rateUnit,
        phoneNumber: phoneNumber,
        notes: notes,
      );
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Entity name cannot be empty');
    }
    final existing = await _existing(entityId);
    final updated = AppEntity(
      id: existing.id,
      workspaceId: existing.workspaceId,
      name: trimmed,
      normalizedName: FirebaseEntityRepository.normalizeName(trimmed),
      type: type,
      createdAt: existing.createdAt,
      attachments: existing.attachments,
      lastUsedAt: DateTime.now().toUtc(),
      clientMutationId: existing.clientMutationId,
      defaultRate: defaultRate,
      rateUnit: _trimmedOrNull(rateUnit) ?? '',
      phoneNumber: _trimmedOrNull(phoneNumber) ?? '',
      notes: _trimmedOrNull(notes) ?? '',
    );
    await mutations.upsertEntity(_upsertPayload(updated));
    return updated;
  }

  @override
  Future<void> deleteEntity(String entityId) async {
    final mutations = _mutations;
    if (mutations == null) {
      return super.deleteEntity(entityId);
    }
    final existing = await _existing(entityId);
    await mutations.deleteEntity(
      workspaceId: existing.workspaceId,
      entityId: entityId,
    );
  }

  @override
  Future<void> saveAttachments({
    required String entityId,
    required List<Map<String, dynamic>> attachments,
  }) async {
    final mutations = _mutations;
    if (mutations == null) {
      return super.saveAttachments(
        entityId: entityId,
        attachments: attachments,
      );
    }
    final existing = await _existing(entityId);
    await mutations.upsertEntity({
      ..._upsertPayload(existing),
      'attachments': jsonSafe(attachments),
    });
  }

  AppEntity _fromRow(LocalRow row) =>
      AppEntity.fromMap('${row['id']}', localRowToMap('entities', row));

  @override
  Stream<List<AppEntity>> watchEntities(
    String workspaceId, {
    String? type,
    int limit = 20,
  }) {
    final byType = type != null && type.isNotEmpty;
    return watchLocalRows(
      _db,
      'SELECT * FROM entities WHERE workspace_id = ? '
      '${byType ? 'AND type = ? ' : ''}'
      'AND last_used_at IS NOT NULL '
      'ORDER BY last_used_at DESC LIMIT ?',
      [workspaceId, if (byType) type, limit],
    ).map((rows) => [for (final row in rows) _fromRow(row)]);
  }

  @override
  Future<FirestorePage<AppEntity>> fetchEntityDirectoryPage(
    String workspaceId, {
    required String type,
    EntityDirectorySort sort = EntityDirectorySort.recent,
    Object? cursor,
    int pageSize = 20,
  }) async {
    final keyset = cursor as LocalPageCursor?;
    final after = keyset?.sortValue as List<Object?>?;
    final where = ['workspace_id = ?', 'type = ?'];
    final args = <Object?>[workspaceId, type];
    final String order;
    switch (sort) {
      case EntityDirectorySort.recent:
        where.addAll([
          'last_used_at IS NOT NULL',
          'normalized_name IS NOT NULL',
        ]);
        order = 'last_used_at DESC, normalized_name ASC, id ASC';
        if (after != null) {
          where.add(
            '(last_used_at < ? OR (last_used_at = ? AND '
            '(normalized_name > ? OR (normalized_name = ? AND id > ?))))',
          );
          args.addAll([after[0], after[0], after[1], after[1], keyset!.id]);
        }
      case EntityDirectorySort.name:
        where.add('normalized_name IS NOT NULL');
        order = 'normalized_name ASC, id ASC';
        if (after != null) {
          where.add(
            '(normalized_name > ? OR (normalized_name = ? AND id > ?))',
          );
          args.addAll([after[1], after[1], keyset!.id]);
        }
      case EntityDirectorySort.id:
        order = 'id ASC';
        if (keyset != null) {
          where.add('id > ?');
          args.add(keyset.id);
        }
    }
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM entities WHERE ${where.join(' AND ')} '
      'ORDER BY $order LIMIT ?',
      [...args, pageSize],
    );
    final last = rows.isEmpty ? null : rows.last;
    return FirestorePage<AppEntity>(
      items: [for (final row in rows) _fromRow(row)],
      hasMore: rows.length == pageSize,
      nextCursor: last == null
          ? cursor
          : LocalPageCursor(
              sortValue: [last['last_used_at'], last['normalized_name']],
              id: '${last['id']}',
            ),
    );
  }

  @override
  Future<List<AppEntity>> searchEntities(
    String workspaceId,
    String query, {
    String? type,
    int limit = 20,
  }) async {
    final normalized = FirebaseEntityRepository.normalizeName(query);
    final byType = type != null && type.isNotEmpty;
    // Same prefix range as the Firestore query ('' upper bound).
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM entities WHERE workspace_id = ? '
      'AND normalized_name >= ? AND normalized_name <= ?'
      '${byType ? ' AND type = ?' : ''}',
      [workspaceId, normalized, '$normalized', if (byType) type],
    );
    final entities = [for (final row in rows) _fromRow(row)]
      ..sort(FirebaseEntityRepository._compareRecentFirst);
    return entities.take(limit).toList(growable: false);
  }

  @override
  Future<AppEntity?> getEntityById(String entityId) async {
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM entities WHERE id = ?',
      [entityId],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<AppEntity?> getEntityByName(
    String workspaceId,
    String name, {
    String? type,
  }) async {
    final byType = type != null && type.isNotEmpty;
    final rows = await getLocalRows(
      _db,
      'SELECT * FROM entities WHERE workspace_id = ? AND normalized_name = ?'
      '${byType ? ' AND type = ?' : ''} LIMIT 1',
      [
        workspaceId,
        FirebaseEntityRepository.normalizeName(name),
        if (byType) type,
      ],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }
}
