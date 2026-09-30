part of 'entity_repository.dart';

/// Entity reads from the local PowerSync replica (spec 004, tasks.md T046).
///
/// Mirrors Firestore semantics exactly, including one subtlety: ordering by a
/// field excludes documents that lack it, so the `lastUsedAt` / `normalizedName`
/// orderings filter `IS NOT NULL`. Writes are the inherited direct writes
/// until US2 moves them behind RPCs.
class LocalEntityRepository extends FirebaseEntityRepository {
  LocalEntityRepository(super.firestore, this._db);

  final Future<PowerSyncDatabase> _db;

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
