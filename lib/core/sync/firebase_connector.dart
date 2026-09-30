import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';

/// Connects PowerSync to the self-hosted sync service using the Firebase ID
/// token the app already holds (research R4: the service validates it against
/// Firebase's public JWKS, so there is no token exchange).
///
/// Sync is read-only replication. Every write goes through the Hive offline
/// queue to the RPC API, so nothing is ever written to the local PowerSync
/// tables and [uploadData] has nothing to send.
class FirebasePowerSyncConnector extends PowerSyncBackendConnector {
  FirebasePowerSyncConnector({
    required BackendConfig config,
    required FirebaseAuth auth,
  }) : _config = config,
       _auth = auth;

  final BackendConfig _config;
  final FirebaseAuth _auth;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null; // Signed out: PowerSync stays disconnected.
    }
    // PowerSync calls this again when the token nears expiry; getIdToken()
    // returns a cached token until it is close to expiring, then refreshes.
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    return PowerSyncCredentials(
      endpoint: _config.syncUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      token: token,
      userId: user.uid,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final batch = await database.getCrudBatch();
    if (batch == null) {
      return;
    }
    // Local writes to synced tables are a programming error: they would never
    // reach the server. Drop them so the next sync restores server state, and
    // make the mistake loud in debug builds.
    assert(() {
      debugPrint(
        '[sync] dropped ${batch.crud.length} local PowerSync write(s); '
        'writes must go through the offline queue',
      );
      return true;
    }());
    await batch.complete();
  }
}
