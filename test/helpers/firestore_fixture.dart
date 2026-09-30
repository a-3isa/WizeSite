import 'dart:convert';

import 'package:buildtrack_app/core/sync/schema.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// One fixture, two backends (spec 004, T033): Firestore-shaped documents are
/// written to `fake_cloud_firestore` as-is and converted to local replica rows
/// the way the migrator and sync rules shape them (data-model.md):
///
/// - camelCase → snake_case, plus the renamed keys;
/// - timestamps → replicated `timestamptz` text, bools → 0/1, lists and maps →
///   JSON text;
/// - fields without a column go to `legacy`; derived tables keep the whole
///   builder output in `payload`.
typedef FixtureDoc = ({
  String collection,
  String id,
  Map<String, dynamic> data,
});

const _tables = {'users': 'user_profiles'};

const _renames = {
  'user_profiles': {'workspaceId': 'active_workspace_id'},
  'workspaces': {'ownerId': 'owner_uid'},
  'memberships': {'userId': 'user_uid'},
};

final Map<String, Set<String>> _columns = {
  for (final table in syncSchema.tables)
    table.name: {for (final column in table.columns) column.name},
};

String localTableFor(String collection) => _tables[collection] ?? collection;

String _snake(String field) =>
    field.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

/// Replicated timestamptz text, e.g. `2026-06-01 08:00:00Z`.
String replicaTimestamp(DateTime value) {
  final iso = value.toUtc().toIso8601String().replaceFirst('T', ' ');
  return iso.replaceFirst(RegExp(r'\.000Z$'), 'Z');
}

Object? _plain(Object? value) => switch (value) {
  final Timestamp t => t.toDate().toUtc().toIso8601String(),
  final DateTime d => d.toUtc().toIso8601String(),
  final Map<dynamic, dynamic> m => {
    for (final e in m.entries) '${e.key}': _plain(e.value),
  },
  final List<dynamic> l => [for (final v in l) _plain(v)],
  _ => value,
};

Object? _cell(Object? value) => switch (value) {
  final Timestamp t => replicaTimestamp(t.toDate()),
  final DateTime d => replicaTimestamp(d),
  final bool b => b ? 1 : 0,
  final Map<dynamic, dynamic> m => jsonEncode(_plain(m)),
  final List<dynamic> l => jsonEncode(_plain(l)),
  _ => value,
};

Map<String, Object?> firestoreDocToLocalRow(FixtureDoc doc) {
  final table = localTableFor(doc.collection);
  final columns = _columns[table];
  if (columns == null) {
    throw ArgumentError('No local table for ${doc.collection}');
  }
  final row = <String, Object?>{'id': doc.id};
  final legacy = <String, Object?>{};
  for (final entry in doc.data.entries) {
    final column = _renames[table]?[entry.key] ?? _snake(entry.key);
    if (columns.contains(column) && column != 'payload' && column != 'legacy') {
      row[column] = _cell(entry.value);
    } else {
      legacy[entry.key] = _plain(entry.value);
    }
  }
  if (columns.contains('payload')) {
    row['payload'] = jsonEncode(_plain(doc.data));
  } else if (columns.contains('legacy') && legacy.isNotEmpty) {
    row['legacy'] = jsonEncode(legacy);
  }
  return row;
}

/// Plain JSON for goldens: DateTimes/Timestamps → UTC ISO, keys sorted.
Object? goldenJson(Object? value) => switch (value) {
  final Timestamp t => t.toDate().toUtc().toIso8601String(),
  final DateTime d => d.toUtc().toIso8601String(),
  final Map<dynamic, dynamic> m => {
    for (final key in m.keys.map((k) => '$k').toList()..sort())
      key: goldenJson(m[key]),
  },
  final Iterable<dynamic> l => [for (final v in l) goldenJson(v)],
  _ => value,
};
