import 'dart:async';

import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:powersync/powersync.dart';

typedef LocalRow = Map<String, Object?>;

List<LocalRow> _asRows(Iterable<Map<String, dynamic>> rows) => [
  for (final row in rows) Map<String, Object?>.from(row),
];

/// Live query against the local replica. A fresh query per listen, so the
/// returned stream can be listened to more than once.
Stream<List<LocalRow>> watchLocalRows(
  Future<PowerSyncDatabase> db,
  String sql, [
  List<Object?> parameters = const [],
]) {
  return Stream.multi((controller) {
    final sub = Stream.fromFuture(db)
        .asyncExpand((database) => database.watch(sql, parameters: parameters))
        .map(_asRows)
        .listen(controller.add, onError: controller.addError);
    controller.onCancel = () {
      unawaited(sub.cancel());
    };
  });
}

/// One-off query against the local replica.
Future<List<LocalRow>> getLocalRows(
  Future<PowerSyncDatabase> db,
  String sql, [
  List<Object?> parameters = const [],
]) async {
  final database = await db;
  return _asRows(await database.getAll(sql, parameters));
}

/// Combines replica rows with the offline queue, the way every repository
/// overlays pending (not yet synced) actions on server data. Emits once both
/// have produced a value, then on every change of either.
///
/// Exceptions thrown by [combine] become stream errors instead of being lost,
/// and cancellation never blocks the consumer (e.g. `.first`).
Stream<T> combineWithQueue<T>({
  required Stream<List<LocalRow>> rows,
  required OfflineActionQueue queue,
  required T Function(List<LocalRow> rows, List<OfflineAction> actions) combine,
}) {
  return Stream.multi((controller) {
    List<LocalRow>? currentRows;
    List<OfflineAction> actions = const [];
    void emit() {
      final base = currentRows;
      if (base == null) return;
      try {
        controller.add(combine(base, actions));
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    final rowSub = rows.listen((next) {
      currentRows = next;
      emit();
    }, onError: controller.addError);
    final queueSub = queue.watch(includeExpiredSynced: true).listen((next) {
      actions = next;
      emit();
    }, onError: controller.addError);
    controller.onCancel = () {
      unawaited(rowSub.cancel());
      unawaited(queueSub.cancel());
    };
  });
}
