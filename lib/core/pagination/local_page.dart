import 'package:powersync/powersync.dart';

/// Position after the last row of a page: the sort value and id of that row.
/// Keyset pagination (not OFFSET) so pages stay stable while rows sync in.
class LocalPageCursor {
  const LocalPageCursor({required this.sortValue, required this.id});

  final Object? sortValue;
  final String id;
}

/// One page of rows from the local replica. Same shape as `RecordPage`
/// (items, hasMore, nextCursor) so list screens can switch without rework.
class LocalPage<T> {
  const LocalPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<T> items;
  final bool hasMore;
  final LocalPageCursor? nextCursor;
}

/// Reads one page of [table] ordered by [orderBy] (then `id`) descending.
///
/// [where]/[whereArgs] scope the query (always include the workspace filter;
/// constitution V: no unbounded reads). [orderBy] must be a column name.
Future<LocalPage<T>> fetchLocalPage<T>(
  PowerSyncDatabase db, {
  required String table,
  required String where,
  required List<Object?> whereArgs,
  required String orderBy,
  required int pageSize,
  required T Function(Map<String, Object?> row) mapRow,
  LocalPageCursor? cursor,
}) async {
  assert(pageSize > 0);
  assert(
    RegExp(r'^[a-z_]+$').hasMatch(table) &&
        RegExp(r'^[a-z_]+$').hasMatch(orderBy),
    'table and orderBy must be plain identifiers',
  );
  final args = <Object?>[...whereArgs];
  var keyset = '';
  if (cursor != null) {
    keyset = ' AND ($orderBy < ? OR ($orderBy = ? AND id < ?))';
    args.addAll([cursor.sortValue, cursor.sortValue, cursor.id]);
  }
  args.add(pageSize + 1); // one extra row tells us whether another page exists
  final rows = await db.getAll(
    'SELECT * FROM $table WHERE ($where)$keyset '
    'ORDER BY $orderBy DESC, id DESC LIMIT ?',
    args,
  );
  final all = [for (final row in rows) Map<String, Object?>.from(row)];
  final hasMore = all.length > pageSize;
  final pageRows = hasMore ? all.sublist(0, pageSize) : all;
  final last = pageRows.isEmpty ? null : pageRows.last;
  return LocalPage<T>(
    items: pageRows.map(mapRow).toList(),
    hasMore: hasMore,
    nextCursor: hasMore && last != null
        ? LocalPageCursor(sortValue: last[orderBy], id: '${last['id']}')
        : null,
  );
}
