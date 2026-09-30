import 'dart:async';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/sync/local_queries.dart';
import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/sync/schema.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

/// A document: its id and its Firestore-shaped field map.
typedef Doc = ({String id, Map<String, dynamic> data});

/// The query vocabulary the providers use against Firestore: equality
/// filters, one optional range on a field, one ordering, a limit. Field names
/// are Firestore field names (camelCase), on either backend.
class DocQuery {
  const DocQuery(
    this.collection, {
    this.equals = const {},
    this.rangeField,
    this.rangeFrom,
    this.rangeTo,
    this.orderBy,
    this.descending = false,
    this.limit,
  });

  final String collection;
  final Map<String, Object?> equals;
  final String? rangeField;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  final String? orderBy;
  final bool descending;
  final int? limit;
}

/// Backend-neutral document reads (spec 004). Providers that queried Firestore
/// directly use this instead, so the same code serves Firebase builds and
/// self-hosted builds (local PowerSync replica).
abstract interface class DocSource {
  Stream<List<Doc>> watch(DocQuery query);
  Future<List<Doc>> get(DocQuery query);
  Stream<Doc?> watchDoc(String collection, String id);
  Future<Doc?> getDoc(String collection, String id);

  /// Number of documents matching [query] (ordering and limit ignored).
  Future<int> count(DocQuery query);
}

class FirestoreDocSource implements DocSource {
  const FirestoreDocSource(this._firestore);

  final FirebaseFirestore _firestore;

  Query<Map<String, dynamic>> _query(DocQuery q) {
    Query<Map<String, dynamic>> query = _firestore.collection(q.collection);
    for (final entry in q.equals.entries) {
      query = query.where(entry.key, isEqualTo: entry.value);
    }
    if (q.rangeField != null && q.rangeFrom != null) {
      query = query.where(q.rangeField!, isGreaterThanOrEqualTo: q.rangeFrom);
    }
    if (q.rangeField != null && q.rangeTo != null) {
      query = query.where(q.rangeField!, isLessThanOrEqualTo: q.rangeTo);
    }
    if (q.orderBy != null) {
      query = query.orderBy(q.orderBy!, descending: q.descending);
    }
    if (q.limit != null) {
      query = query.limit(q.limit!);
    }
    return query;
  }

  static List<Doc> _docs(QuerySnapshot<Map<String, dynamic>> snap) => [
    for (final doc in snap.docs) (id: doc.id, data: doc.data()),
  ];

  @override
  Stream<List<Doc>> watch(DocQuery query) =>
      _query(query).snapshots().map(_docs);

  @override
  Future<List<Doc>> get(DocQuery query) async =>
      _docs(await _query(query).get());

  @override
  Stream<Doc?> watchDoc(String collection, String id) => _firestore
      .collection(collection)
      .doc(id)
      .snapshots()
      .map((snap) => snap.exists ? (id: snap.id, data: snap.data()!) : null);

  @override
  Future<Doc?> getDoc(String collection, String id) async {
    final snap = await _firestore.collection(collection).doc(id).get();
    return snap.exists ? (id: snap.id, data: snap.data()!) : null;
  }

  @override
  Future<int> count(DocQuery query) async {
    final snap = await _query(
      DocQuery(
        query.collection,
        equals: query.equals,
        rangeField: query.rangeField,
        rangeFrom: query.rangeFrom,
        rangeTo: query.rangeTo,
      ),
    ).count().get();
    return snap.count ?? 0;
  }
}

/// Reads the local replica with the same semantics as [FirestoreDocSource].
class LocalDocSource implements DocSource {
  LocalDocSource(this._db);

  final Future<PowerSyncDatabase> _db;

  /// Firestore collection → local table.
  static const _tables = {'users': 'user_profiles'};

  /// Per-table field renames (data-model.md), Firestore field → column.
  static const _renames = {
    'user_profiles': {'workspaceId': 'active_workspace_id'},
    'workspaces': {'ownerId': 'owner_uid'},
    'memberships': {'userId': 'user_uid'},
  };

  static final Map<String, Set<String>> _columns = {
    for (final table in syncSchema.tables)
      table.name: {'id', for (final column in table.columns) column.name},
  };

  static String _table(String collection) {
    final table = _tables[collection] ?? collection;
    if (!_columns.containsKey(table)) {
      throw ArgumentError('Collection $collection is not in the local replica');
    }
    return table;
  }

  static String _snake(String field) =>
      field.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  /// SQL expression for a Firestore field: a real column when there is one,
  /// otherwise the field inside the derived `payload` (or `legacy`) JSON.
  static String _expr(String table, String field) {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(field)) {
      throw ArgumentError('Unsupported field name: $field');
    }
    final column = _renames[table]?[field] ?? _snake(field);
    final columns = _columns[table]!;
    if (columns.contains(column)) return column;
    final jsonColumn = columns.contains('payload') ? 'payload' : 'legacy';
    return "json_extract($jsonColumn, '\$.$field')";
  }

  static Object? _value(Object? value) => switch (value) {
    true => 1,
    false => 0,
    final DateTime date => date.toUtc().toIso8601String(),
    _ => value,
  };

  (String, List<Object?>) _sql(DocQuery q) {
    final table = _table(q.collection);
    final where = <String>[];
    final args = <Object?>[];
    for (final entry in q.equals.entries) {
      final expr = _expr(table, entry.key);
      if (entry.value == null) {
        where.add('$expr IS NULL');
      } else {
        where.add('$expr = ?');
        args.add(_value(entry.value));
      }
    }
    if (q.rangeField != null && q.rangeFrom != null) {
      where.add('julianday(${_expr(table, q.rangeField!)}) >= julianday(?)');
      args.add(_value(q.rangeFrom));
    }
    if (q.rangeField != null && q.rangeTo != null) {
      where.add('julianday(${_expr(table, q.rangeField!)}) <= julianday(?)');
      args.add(_value(q.rangeTo));
    }
    var order = '';
    if (q.orderBy != null) {
      final expr = _expr(table, q.orderBy!);
      // Firestore's orderBy excludes documents that lack the field.
      where.add('$expr IS NOT NULL');
      order = ' ORDER BY $expr ${q.descending ? 'DESC' : 'ASC'}, id ASC';
    }
    final limit = q.limit == null ? '' : ' LIMIT ${q.limit}';
    final whereSql = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
    return ('SELECT * FROM $table$whereSql$order$limit', args);
  }

  static Doc _doc(String table, LocalRow row) =>
      (id: '${row['id']}', data: localRowToMap(table, row));

  @override
  Stream<List<Doc>> watch(DocQuery query) {
    final (sql, args) = _sql(query);
    final table = _table(query.collection);
    return watchLocalRows(
      _db,
      sql,
      args,
    ).map((rows) => [for (final row in rows) _doc(table, row)]);
  }

  @override
  Future<List<Doc>> get(DocQuery query) async {
    final (sql, args) = _sql(query);
    final table = _table(query.collection);
    final rows = await getLocalRows(_db, sql, args);
    return [for (final row in rows) _doc(table, row)];
  }

  @override
  Stream<Doc?> watchDoc(String collection, String id) {
    final table = _table(collection);
    return watchLocalRows(_db, 'SELECT * FROM $table WHERE id = ?', [
      id,
    ]).map((rows) => rows.isEmpty ? null : _doc(table, rows.first));
  }

  @override
  Future<Doc?> getDoc(String collection, String id) async {
    final table = _table(collection);
    final rows = await getLocalRows(_db, 'SELECT * FROM $table WHERE id = ?', [
      id,
    ]);
    return rows.isEmpty ? null : _doc(table, rows.first);
  }

  @override
  Future<int> count(DocQuery query) async {
    final (sql, args) = _sql(
      DocQuery(
        query.collection,
        equals: query.equals,
        rangeField: query.rangeField,
        rangeFrom: query.rangeFrom,
        rangeTo: query.rangeTo,
      ),
    );
    final rows = await getLocalRows(
      _db,
      sql.replaceFirst('SELECT *', 'SELECT count(*) AS n'),
      args,
    );
    return (rows.first['n'] as int?) ?? 0;
  }
}

final docSourceProvider = Provider<DocSource>((ref) {
  if (BackendConfig.fromEnvironment.useSelfHostedBackend) {
    return LocalDocSource(ref.watch(localDatabaseProvider));
  }
  return FirestoreDocSource(ref.watch(firestoreProvider));
});
