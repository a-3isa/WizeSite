import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'offline sync providers split actions by status and resolution',
    () async {
      final now = DateTime.utc(2026, 6, 17, 10);
      final pending = _action(
        id: 'pending_1',
        status: OfflineActionStatus.pending,
        createdAt: now,
      );
      final failed = _action(
        id: 'failed_1',
        status: OfflineActionStatus.failed,
        createdAt: now,
      );
      final deadLetter = _action(
        id: 'dead_1',
        status: OfflineActionStatus.deadLetter,
        createdAt: now,
      );
      final resolved = _action(
        id: 'resolved_1',
        status: OfflineActionStatus.synced,
        createdAt: now,
        resolutionType: OfflineActionResolutionType.skippedNewerVersion,
        resolutionAt: now,
      );
      final syncedWithoutResolution = _action(
        id: 'synced_1',
        status: OfflineActionStatus.synced,
        createdAt: now,
      );

      final container = ProviderContainer(
        overrides: [
          offlineSyncActionsProvider.overrideWith(
            (ref) => Stream.value([
              pending,
              failed,
              deadLetter,
              resolved,
              syncedWithoutResolution,
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(offlineSyncActionsProvider.future);

      expect(container.read(offlinePendingActionsProvider).requireValue, [
        pending,
      ]);
      expect(container.read(offlineFailedActionsProvider).requireValue, [
        failed,
      ]);
      expect(container.read(offlineDeadLetterActionsProvider).requireValue, [
        deadLetter,
      ]);
      expect(container.read(offlineResolvedActionsProvider).requireValue, [
        resolved,
      ]);
    },
  );
}

OfflineAction _action({
  required String id,
  required String status,
  required DateTime createdAt,
  String? resolutionType,
  DateTime? resolutionAt,
}) {
  return OfflineAction(
    id: id,
    type: 'update_expense',
    payload: {'expenseId': id},
    createdAt: createdAt,
    status: status,
    resolutionType: resolutionType,
    resolutionAt: resolutionAt,
    resolutionTargetId: resolutionType == null ? null : id,
  );
}
