import 'package:flutter_riverpod/flutter_riverpod.dart';

/// For v1, each user has exactly one active workspace.
final activeWorkspaceIdProvider = StateProvider<String?>((ref) {
  return null;
});

final activeUserIdProvider = StateProvider<String?>((ref) {
  return null;
});
