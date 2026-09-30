import 'package:buildtrack_app/core/services/attachment_cache_service.dart';
import 'package:hive/hive.dart';

/// Drops queued financial mutations that belong to the signed-out user so the
/// next account cannot drain them.
class LocalSessionCleanup {
  static Future<void> clearQueuedUserData() async {
    await _clearBox('offline_actions');
    await _clearBox('pending_attachments');
    // Same readiness signal as below: no open queue box means the app never
    // finished starting (early auth failure, widget tests), so there is no
    // cache to clear and the platform directory lookup may never answer.
    if (Hive.isBoxOpen('offline_actions')) {
      await AttachmentCacheService.clearDefault();
    }
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
