import 'dart:async';

import 'package:buildtrack_app/core/sync/doc_source.dart';

/// In-memory [DocSource] for widget tests (spec 004): no database, so it works
/// under the widget tester's fake async. Tests write Firestore-shaped
/// documents with `collection(...).doc(...).set/update/delete`; queries follow
/// the same rules as [LocalDocSource] (equality, one date range, ordering that
/// skips documents without the field, id as tie-break, limit).
class MemoryDocSource implements DocSource {
  final Map<String, Map<String, Map<String, dynamic>>> _docs = {};
  final _changes = StreamController<void>.broadcast(sync: true);

  MemoryCollection collection(String name) => MemoryCollection._(this, name);

  void _write(String collection, String id, Map<String, dynamic>? data) {
    final docs = _docs.putIfAbsent(collection, () => {});
    if (data == null) {
      docs.remove(id);
    } else {
      docs[id] = Map<String, dynamic>.of(data);
    }
    _changes.add(null);
  }

  Map<String, dynamic>? _read(String collection, String id) =>
      _docs[collection]?[id];

  static DateTime? _date(Object? value) => switch (value) {
    final DateTime d => d,
    final String s => DateTime.tryParse(s),
    _ => null,
  };

  static int _compare(Object? a, Object? b) {
    final da = _date(a);
    final db = _date(b);
    if (da != null && db != null) return da.compareTo(db);
    if (a is num && b is num) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }

  List<Doc> _query(DocQuery q) {
    final docs = <Doc>[
      for (final entry in (_docs[q.collection] ?? const {}).entries)
        (id: entry.key, data: entry.value),
    ];
    bool matches(Doc doc) {
      for (final filter in q.equals.entries) {
        if (doc.data[filter.key] != filter.value) return false;
      }
      if (q.rangeField != null) {
        final value = _date(doc.data[q.rangeField]);
        if (q.rangeFrom != null &&
            (value == null || value.isBefore(q.rangeFrom!))) {
          return false;
        }
        if (q.rangeTo != null && (value == null || value.isAfter(q.rangeTo!))) {
          return false;
        }
      }
      if (q.orderBy != null && doc.data[q.orderBy] == null) return false;
      return true;
    }

    final result = docs.where(matches).toList();
    if (q.orderBy != null) {
      result.sort((a, b) {
        final byField = _compare(a.data[q.orderBy], b.data[q.orderBy]);
        if (byField != 0) return q.descending ? -byField : byField;
        return a.id.compareTo(b.id);
      });
    }
    final limit = q.limit;
    return limit == null || result.length <= limit
        ? result
        : result.sublist(0, limit);
  }

  /// Emits the current result, then a new one on every write. The change
  /// subscription starts on listen, so no write after that is missed.
  Stream<T> _live<T>(T Function() read) {
    late final StreamController<T> controller;
    StreamSubscription<void>? changes;
    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        changes = _changes.stream.listen((_) => controller.add(read()));
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  @override
  Stream<List<Doc>> watch(DocQuery query) => _live(() => _query(query));

  @override
  Future<List<Doc>> get(DocQuery query) async => _query(query);

  @override
  Stream<Doc?> watchDoc(String collection, String id) =>
      _live(() => _docOrNull(collection, id));

  @override
  Future<Doc?> getDoc(String collection, String id) async =>
      _docOrNull(collection, id);

  Doc? _docOrNull(String collection, String id) {
    final data = _read(collection, id);
    return data == null ? null : (id: id, data: data);
  }

  @override
  Future<int> count(DocQuery query) async => _query(
    DocQuery(
      query.collection,
      equals: query.equals,
      rangeField: query.rangeField,
      rangeFrom: query.rangeFrom,
      rangeTo: query.rangeTo,
    ),
  ).length;
}

class MemoryCollection {
  MemoryCollection._(this._source, this._name);

  final MemoryDocSource _source;
  final String _name;

  MemoryDocRef doc(String id) => MemoryDocRef._(_source, _name, id);
}

class MemoryDocRef {
  MemoryDocRef._(this._source, this._collection, this.id);

  final MemoryDocSource _source;
  final String _collection;
  final String id;

  Future<void> set(Map<String, dynamic> data, {bool merge = false}) async {
    final current = merge ? _source._read(_collection, id) : null;
    _source._write(_collection, id, {...?current, ...data});
  }

  Future<void> update(Map<String, dynamic> data) async {
    final current = _source._read(_collection, id);
    if (current == null) {
      throw StateError('No document $_collection/$id to update');
    }
    _source._write(_collection, id, {...current, ...data});
  }

  Future<void> delete() async => _source._write(_collection, id, null);

  Map<String, dynamic>? get data => _source._read(_collection, id);
}
