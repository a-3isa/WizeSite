import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Archives one record (expense, payment, …) by id, returning the existing
/// [MutationResult] so the orchestration can detect offline-queued writes.
typedef ArchiveOneCallback = Future<MutationResult> Function(String id);

/// Asks the user to confirm archiving [count] records. Returns `true` to
/// proceed, `false` to cancel.
typedef ConfirmArchiveCallback = Future<bool> Function(int count);

/// Outcome of a confirmed bulk-archive run.
class BulkArchiveResult {
  const BulkArchiveResult({
    required this.total,
    required this.succeeded,
    required this.failed,
    this.queued = false,
    this.cancelled = false,
  });

  const BulkArchiveResult.cancelled(int total)
    : this(
        total: total,
        succeeded: const [],
        failed: const [],
        cancelled: true,
      );

  final int total;
  final List<String> succeeded;
  final List<String> failed;

  /// True when any archived record was queued for offline sync.
  final bool queued;

  /// True when the user declined the confirmation.
  final bool cancelled;

  /// Every selected record was archived.
  bool get isComplete => !cancelled && failed.isEmpty && succeeded.isNotEmpty;

  /// Some records archived and some failed.
  bool get isPartialFailure => failed.isNotEmpty && succeeded.isNotEmpty;

  /// Every record failed.
  bool get isTotalFailure =>
      !cancelled && succeeded.isEmpty && failed.isNotEmpty;
}

/// Immutable selection + progress snapshot for the bulk-archive flow.
class BulkArchiveState {
  const BulkArchiveState({
    this.selectedIds = const {},
    this.isInProgress = false,
  });

  final Set<String> selectedIds;
  final bool isInProgress;

  bool get isSelecting => selectedIds.isNotEmpty;
  int get selectedCount => selectedIds.length;
  bool isSelected(String id) => selectedIds.contains(id);

  BulkArchiveState copyWith({Set<String>? selectedIds, bool? isInProgress}) {
    return BulkArchiveState(
      selectedIds: selectedIds ?? this.selectedIds,
      isInProgress: isInProgress ?? this.isInProgress,
    );
  }
}

/// Reusable selection + confirmed per-record archive orchestration shared by the
/// expenses and payments lists.
///
/// It does not know how to archive a specific record type; callers pass an
/// [ArchiveOneCallback] bound to the existing archive mutation. Failures are
/// collected per record so a partial failure still archives what it can and
/// keeps only the failed records selected for retry.
class TransactionBulkArchiveController extends StateNotifier<BulkArchiveState> {
  TransactionBulkArchiveController() : super(const BulkArchiveState());

  void toggle(String id) {
    final next = Set<String>.of(state.selectedIds);
    if (!next.add(id)) {
      next.remove(id);
    }
    state = state.copyWith(selectedIds: next);
  }

  void select(String id) {
    if (state.selectedIds.contains(id)) return;
    state = state.copyWith(selectedIds: {...state.selectedIds, id});
  }

  void selectAll(Iterable<String> ids) {
    state = state.copyWith(selectedIds: {...state.selectedIds, ...ids});
  }

  void clear() {
    if (state.selectedIds.isEmpty && !state.isInProgress) return;
    state = const BulkArchiveState();
  }

  /// Confirms, then archives every selected record one by one.
  ///
  /// Returns `null` when nothing is selected, a cancelled result when the user
  /// declines, otherwise a [BulkArchiveResult] describing the outcome. On
  /// success the selection is cleared; on partial failure only the failed ids
  /// remain selected.
  Future<BulkArchiveResult?> archiveSelected({
    required ArchiveOneCallback archiveOne,
    required ConfirmArchiveCallback confirm,
  }) async {
    final ids = state.selectedIds.toList();
    if (ids.isEmpty) return null;

    final confirmed = await confirm(ids.length);
    if (!confirmed) {
      return BulkArchiveResult.cancelled(ids.length);
    }

    state = state.copyWith(isInProgress: true);

    final succeeded = <String>[];
    final failed = <String>[];
    var queued = false;

    for (final id in ids) {
      try {
        final result = await archiveOne(id);
        succeeded.add(id);
        if (result.queued) queued = true;
      } catch (_) {
        failed.add(id);
      }
    }

    // Keep only the failed records selected so the user can retry them.
    state = BulkArchiveState(selectedIds: failed.toSet());

    return BulkArchiveResult(
      total: ids.length,
      succeeded: succeeded,
      failed: failed,
      queued: queued,
    );
  }
}

/// Provides a fresh, auto-disposed bulk-archive controller per list screen.
final transactionBulkArchiveControllerProvider =
    StateNotifierProvider.autoDispose<
      TransactionBulkArchiveController,
      BulkArchiveState
    >((ref) => TransactionBulkArchiveController());
