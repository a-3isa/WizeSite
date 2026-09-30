import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/sync/powersync_db.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show SyncStatus;

/// Where the signed-in user's local replica stands (spec 004, T054).
enum SyncGatePhase {
  /// Data is on the device (or this build reads Firebase): show the app.
  ready,

  /// First sync in progress: data is on its way.
  loading,

  /// Never synced and not connected: an empty workspace would be a lie.
  offline,
}

/// Maps replica status flags to a gate phase. Once any complete sync has
/// been stored on the device, the app opens offline from then on.
SyncGatePhase syncGatePhaseFor({
  required bool? hasSynced,
  required bool connected,
  required bool connecting,
}) {
  if (hasSynced ?? false) return SyncGatePhase.ready;
  if (connected || connecting) return SyncGatePhase.loading;
  return SyncGatePhase.offline;
}

SyncGatePhase _phaseOf(SyncStatus status) => syncGatePhaseFor(
  hasSynced: status.hasSynced,
  connected: status.connected,
  connecting: status.connecting,
);

final syncGatePhaseProvider = StreamProvider<SyncGatePhase>((ref) async* {
  final db = await ref.watch(syncDatabaseProvider.future);
  if (db == null) {
    yield SyncGatePhase.ready;
    return;
  }
  yield _phaseOf(db.currentStatus);
  yield* db.statusStream.map(_phaseOf).distinct();
});

/// Shows [child] once the user's data is on the device. Before the first
/// complete sync for this uid it shows a "connect to load your data" state
/// instead of an empty workspace (spec edge case).
class SyncGate extends ConsumerWidget {
  const SyncGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(syncGatePhaseProvider).value ?? SyncGatePhase.ready;
    if (phase == SyncGatePhase.ready) return child;

    final l10n = AppLocalizations.of(context);
    final loading = phase == SyncGatePhase.loading;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppEmptyState(
              icon: loading ? Icons.cloud_download_outlined : Icons.cloud_off,
              message: l10n.t(
                loading ? 'syncGateLoadingMessage' : 'syncGateOfflineMessage',
              ),
            ),
            if (loading) ...[
              const SizedBox(height: 16),
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
