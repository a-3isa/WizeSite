import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

final offlineActionQueueProvider = Provider<OfflineActionQueue>((ref) {
  final box = Hive.box<String>('offline_actions');
  return OfflineActionQueue(box);
});

final offlinePendingCountProvider = StateProvider<int>((ref) => 0);

final offlineDeadLetterCountProvider = StateProvider<int>((ref) => 0);

enum OfflineSyncFailureType {
  quota,
  unauthenticated,
  invalidTarget,
  permission,
  generic,
}

class OfflineSyncNotice {
  const OfflineSyncNotice({required this.actionId, required this.type});

  final String actionId;
  final OfflineSyncFailureType type;
}

final offlineSyncNoticeProvider = StateProvider<OfflineSyncNotice?>(
  (ref) => null,
);

final offlineLastNotifiedDeadLetterIdProvider = StateProvider<String?>(
  (ref) => null,
);

class AppUiNotice {
  const AppUiNotice({required this.id, required this.message});

  final String id;
  final String message;
}

final appUiNoticeProvider = StateProvider<AppUiNotice?>((ref) => null);

void pushAppUiNotice(WidgetRef ref, String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) {
    return;
  }
  ref.read(appUiNoticeProvider.notifier).state = AppUiNotice(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    message: trimmed,
  );
}
