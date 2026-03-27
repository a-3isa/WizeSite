import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

final offlineActionQueueProvider = Provider<OfflineActionQueue>((ref) {
  final box = Hive.box<String>('offline_actions');
  return OfflineActionQueue(box);
});

final offlinePendingCountProvider = StateProvider<int>((ref) => 0);

final offlineDeadLetterCountProvider = StateProvider<int>((ref) => 0);

enum OfflineSyncFailureType { quota, unauthenticated, generic }

class OfflineSyncNotice {
  const OfflineSyncNotice({
    required this.actionId,
    required this.type,
  });

  final String actionId;
  final OfflineSyncFailureType type;
}

final offlineSyncNoticeProvider = StateProvider<OfflineSyncNotice?>(
  (ref) => null,
);

final offlineLastNotifiedDeadLetterIdProvider = StateProvider<String?>(
  (ref) => null,
);
