import 'package:hive/hive.dart';

/// Drops queued financial mutations that belong to the signed-out user so the
/// next account cannot drain them.
class LocalSessionCleanup {
  static Future<void> clearQueuedUserData() async {
    await _clearBox('offline_actions');
    await _clearBox('pending_attachments');
  }

  /// Only clears boxes that are already open. `main()` opens both queue boxes
  /// at startup, so a closed box means Hive was never initialised (early auth
  /// failure, widget tests). Opening it here would leave an unhandled error on
  /// Hive's internal opening future even though this call catches it.
  static Future<void> _clearBox(String name) async {
    if (!Hive.isBoxOpen(name)) {
      return;
    }
    try {
      await Hive.box<String>(name).clear();
    } catch (_) {
      // Sign-out must not fail on local cleanup.
    }
  }
}
