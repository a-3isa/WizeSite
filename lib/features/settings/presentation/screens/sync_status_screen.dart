import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncStatusScreen extends ConsumerWidget {
  const SyncStatusScreen({super.key, this.actions, this.onRetryAction});

  final List<OfflineAction>? actions;
  final Future<void> Function(String actionId)? onRetryAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final injectedActions = actions;
    if (injectedActions != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.t('syncStatus'))),
        body: _SyncStatusContent(
          actions: injectedActions,
          l10n: l10n,
          onRetryAction: onRetryAction,
        ),
      );
    }

    final actionsAsync = ref.watch(offlineSyncActionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('syncStatus'))),
      body: actionsAsync.whenStale(
        data: (actions) => _SyncStatusContent(
          actions: actions,
          l10n: l10n,
          onRetryAction: onRetryAction,
        ),
        error: (error, _) => AppRecoverableError(
          message: l10n.t('offlineSyncStatusUnavailable'),
        ),
        loading: () => const AppLoadingSkeleton(lineCount: 6),
      ),
    );
  }
}

class _SyncStatusContent extends ConsumerWidget {
  const _SyncStatusContent({
    required this.actions,
    required this.l10n,
    this.onRetryAction,
  });

  final List<OfflineAction> actions;
  final AppLocalizations l10n;
  final Future<void> Function(String actionId)? onRetryAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = _byStatus(OfflineActionStatus.pending);
    final failed = _byStatus(OfflineActionStatus.failed);
    final deadLetters = _byStatus(OfflineActionStatus.deadLetter);
    final resolved = actions
        .where(
          (action) =>
              action.status == OfflineActionStatus.synced &&
              action.resolutionType != null,
        )
        .toList();

    if (actions.isEmpty) {
      return AppEmptyState(
        icon: Icons.sync_rounded,
        message: l10n.t('syncStatusEmpty'),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SyncSection(
          title: l10n.t('syncPending'),
          actions: pending,
          emptyMessage: l10n.t('syncNoPending'),
          color: AppColors.warning,
          icon: Icons.cloud_upload_outlined,
          l10n: l10n,
        ),
        _SyncSection(
          title: l10n.t('syncFailed'),
          actions: failed,
          emptyMessage: l10n.t('syncNoFailed'),
          color: AppColors.danger,
          icon: Icons.sync_problem_outlined,
          l10n: l10n,
          onRetry: (action) => _retry(ref, action.id),
        ),
        _SyncSection(
          title: l10n.t('syncNeedsAttention'),
          actions: deadLetters,
          emptyMessage: l10n.t('syncNoNeedsAttention'),
          color: AppColors.danger,
          icon: Icons.report_problem_outlined,
          l10n: l10n,
          onRetry: (action) => _retry(ref, action.id),
        ),
        _SyncSection(
          title: l10n.t('syncRecentlyResolved'),
          actions: resolved,
          emptyMessage: l10n.t('syncNoResolved'),
          color: AppColors.success,
          icon: Icons.check_circle_outline,
          l10n: l10n,
        ),
      ],
    );
  }

  List<OfflineAction> _byStatus(String status) =>
      actions.where((action) => action.status == status).toList();

  Future<void> _retry(WidgetRef ref, String actionId) async {
    final injectedRetry = onRetryAction;
    if (injectedRetry != null) {
      await injectedRetry(actionId);
      return;
    }
    await ref.read(offlineActionQueueProvider).retryAction(actionId);
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection({
    required this.title,
    required this.actions,
    required this.emptyMessage,
    required this.color,
    required this.icon,
    required this.l10n,
    this.onRetry,
  });

  final String title;
  final List<OfflineAction> actions;
  final String emptyMessage;
  final Color color;
  final IconData icon;
  final AppLocalizations l10n;
  final Future<void> Function(OfflineAction action)? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          if (actions.isEmpty)
            Text(
              emptyMessage,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textBody),
            )
          else
            ...actions.map(
              (action) => _SyncActionTile(
                action: action,
                color: color,
                icon: icon,
                l10n: l10n,
                onRetry: onRetry == null ? null : () => onRetry!(action),
              ),
            ),
        ],
      ),
    );
  }
}

class _SyncActionTile extends StatelessWidget {
  const _SyncActionTile({
    required this.action,
    required this.color,
    required this.icon,
    required this.l10n,
    this.onRetry,
  });

  final OfflineAction action;
  final Color color;
  final IconData icon;
  final AppLocalizations l10n;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final reason = _reason();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _actionLabel(action.type),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timestamp(action),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 4),
                    Text(reason),
                  ],
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: Text(l10n.t('retrySync'))),
          ],
        ),
      ),
    );
  }

  String? _reason() {
    if (action.resolutionType ==
        OfflineActionResolutionType.skippedNewerVersion) {
      return l10n.t('syncResolvedNewerKept');
    }
    if (action.resolutionType == OfflineActionResolutionType.applied) {
      return l10n.t('syncResolvedApplied');
    }
    return action.lastError;
  }

  String _timestamp(OfflineAction action) {
    final date = action.resolutionAt ?? action.syncedAt ?? action.createdAt;
    return date.toLocal().toString().split('.').first;
  }

  String _actionLabel(String type) => type.replaceAll('_', ' ');
}
