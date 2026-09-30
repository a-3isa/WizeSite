import 'dart:io';

import 'package:buildtrack_app/core/sync/schema.dart';
import 'package:powersync/powersync.dart';

/// A throwaway local replica with the real [syncSchema], for repository tests
/// (replaces `fake_cloud_firestore`, tasks.md T027). Never connected to a
/// sync service: tests load rows directly with [seedRows].
///
/// Call [LocalTestDb.dispose] in `tearDown`/`addTearDown`.
class LocalTestDb {
  LocalTestDb._(this.db, this._dir);

  final PowerSyncDatabase db;
  final Directory _dir;

  static Future<LocalTestDb> open() async {
    final dir = await Directory.systemTemp.createTemp('wizesite_local_db_');
    final db = PowerSyncDatabase(
      schema: syncSchema,
      path: '${dir.path}${Platform.pathSeparator}test.db',
    );
    await db.initialize();
    return LocalTestDb._(db, dir);
  }

  /// Inserts rows as the sync service would deliver them. Each row must carry
  /// an `id`; other keys must be columns of [table] in [syncSchema].
  Future<void> seedRows(String table, List<Map<String, Object?>> rows) async {
    await db.writeTransaction((tx) async {
      for (final row in rows) {
        final columns = row.keys.toList();
        final placeholders = List.filled(columns.length, '?').join(', ');
        await tx.execute(
          'INSERT INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
          columns.map((c) => row[c]).toList(),
        );
      }
    });
  }

  Future<void> dispose() async {
    await db.close();
    if (await _dir.exists()) {
      await _dir.delete(recursive: true);
    }
  }
}
