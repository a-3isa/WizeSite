import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/sync/firebase_connector.dart';
import 'package:buildtrack_app/core/sync/schema.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

/// Opens the local replica for [uid]. One database file per Firebase user, so
/// a sign-out/sign-in as someone else never shows the previous user's data.
Future<PowerSyncDatabase> openSyncDatabase(String uid) async {
  final dir = await getApplicationSupportDirectory();
  final safeUid = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final db = PowerSyncDatabase(
    schema: syncSchema,
    path: p.join(dir.path, 'sync_$safeUid.db'),
  );
  await db.initialize();
  return db;
}

/// The signed-in user's local replica, connected to the sync service.
///
/// Null when nobody is signed in.
/// Rebuilt whenever the Firebase user changes; the previous user's database is
/// disconnected and closed.
final syncDatabaseProvider = FutureProvider<PowerSyncDatabase?>((ref) async {
  const config = BackendConfig.fromEnvironment;
  final auth = ref.watch(firebaseAuthProvider);
  final user = await ref.watch(_firebaseUserProvider.future);
  if (user == null) {
    return null;
  }
  final db = await openSyncDatabase(user.uid);
  ref.onDispose(() async {
    await db.disconnect();
    await db.close();
  });
  await db.connect(
    connector: FirebasePowerSyncConnector(config: config, auth: auth),
  );
  return db;
});

/// The replica as a future, for repositories (which are synchronous
/// providers). Fails loudly when nobody is signed in.
final localDatabaseProvider = Provider<Future<PowerSyncDatabase>>((ref) {
  return ref.watch(syncDatabaseProvider.future).then((db) {
    if (db == null) {
      throw StateError('Local database unavailable: no signed-in user.');
    }
    return db;
  });
});

final _firebaseUserProvider = StreamProvider((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});
