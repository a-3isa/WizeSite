import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// Local, synchronous cache for the last-used session context so the app can
/// start straight on the dashboard without waiting for a network round-trip.
///
/// Backed by the already-open `app_prefs` Hive box (see `main.dart`). All reads
/// degrade gracefully to `null` when the box is not open (e.g. in widget tests
/// that do not bootstrap Hive), which keeps callers on their cold-start path.
class WorkspaceCache {
  const WorkspaceCache();

  static const String boxName = 'app_prefs';
  static const String activeUserIdKey = 'active_user_id';
  static const String activeWorkspaceIdKey = 'active_workspace_id';
  static const String workspaceSummariesKey = 'workspace_summaries';

  Box<String>? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box<String>(boxName) : null;

  String? get activeUserId => _nonEmpty(_box?.get(activeUserIdKey));

  String? get activeWorkspaceId => _nonEmpty(_box?.get(activeWorkspaceIdKey));

  String? get workspaceSummariesJson =>
      _nonEmpty(_box?.get(workspaceSummariesKey));

  void setActiveUserId(String? value) => _put(activeUserIdKey, value);

  void setActiveWorkspaceId(String? value) => _put(activeWorkspaceIdKey, value);

  void setWorkspaceSummariesJson(String? value) =>
      _put(workspaceSummariesKey, value);

  void _put(String key, String? value) {
    final box = _box;
    if (box == null) {
      return;
    }
    if (value == null || value.isEmpty) {
      box.delete(key);
    } else {
      box.put(key, value);
    }
  }

  static String? _nonEmpty(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }
}

final workspaceCacheProvider = Provider<WorkspaceCache>(
  (ref) => const WorkspaceCache(),
);
