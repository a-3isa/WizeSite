import 'package:buildtrack_app/core/sync/doc_source.dart';

import 'firestore_fixture.dart';
import 'local_db.dart';

/// Firestore-shaped test data on the local replica (spec 004): tests write
/// documents with `collection(...).doc(...).set/update/delete` as they did
/// against fake Firestore, and the rows land in a real local database the way
/// the migrator and sync rules shape them. Providers read them through
/// [source], the same [LocalDocSource] the app uses.
class LocalFixtureStore {
  LocalFixtureStore._(this.local);

  final LocalTestDb local;
  final Map<String, Map<String, Map<String, dynamic>>> _docs = {};
  var _nextAutoId = 0;

  static Future<LocalFixtureStore> open() async =>
      LocalFixtureStore._(await LocalTestDb.open());

  LocalDocSource get source => LocalDocSource(Future.value(local.db));

  FixtureCollection collection(String name) => FixtureCollection._(this, name);

  Future<void> dispose() => local.dispose();

  Map<String, dynamic>? _read(String collection, String id) =>
      _docs[collection]?[id];

  Future<void> _write(
    String collection,
    String id,
    Map<String, dynamic>? data,
  ) async {
    final table = localTableFor(collection);
    final docs = _docs.putIfAbsent(collection, () => {});
    if (data == null) {
      docs.remove(id);
    } else {
      docs[id] = data;
    }
    final row = data == null
        ? null
        : firestoreDocToLocalRow((collection: collection, id: id, data: data));
    await local.db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM $table WHERE id = ?', [id]);
      if (row != null) {
        final columns = row.keys.toList();
        final placeholders = List.filled(columns.length, '?').join(', ');
        await tx.execute(
          'INSERT INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
          columns.map((c) => row[c]).toList(),
        );
      }
    });
  }
}

class FixtureCollection {
  FixtureCollection._(this._store, this._name);

  final LocalFixtureStore _store;
  final String _name;

  FixtureDocRef doc(String id) => FixtureDocRef._(_store, _name, id);

  /// Adds a document with a generated id, like Firestore's `add`.
  Future<FixtureDocRef> add(Map<String, dynamic> data) async {
    final ref = doc('${_name}_auto_${_store._nextAutoId++}');
    await ref.set(data);
    return ref;
  }
}

class FixtureDocRef {
  FixtureDocRef._(this._store, this._collection, this.id);

  final LocalFixtureStore _store;
  final String _collection;
  final String id;

  Future<void> set(Map<String, dynamic> data, {bool merge = false}) {
    final current = merge ? _store._read(_collection, id) : null;
    return _store._write(_collection, id, {...?current, ...data});
  }

  Future<void> update(Map<String, dynamic> data) {
    final current = _store._read(_collection, id);
    if (current == null) {
      throw StateError('No document $_collection/$id to update');
    }
    return _store._write(_collection, id, {...current, ...data});
  }

  Future<void> delete() => _store._write(_collection, id, null);

  Map<String, dynamic>? get data => _store._read(_collection, id);
}
