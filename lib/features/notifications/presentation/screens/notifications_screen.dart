import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/features/notifications/data/notification_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final Set<String> _markingRead = {};

  void _markDisplayedRead(Iterable<String> ids) {
    final pending = ids.where((id) => _markingRead.add(id)).toList();
    if (pending.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(notificationRepositoryProvider).markRead(pending);
      } finally {
        _markingRead.removeAll(pending);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notificationsAsync = ref.watch(notificationItemsProvider);
    return AppBackScope(
      fallbackRoute: AppRoutes.dashboard,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('notificationsTitle'),
          fallbackRoute: AppRoutes.dashboard,
        ),
        body: notificationsAsync.when(
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AppEmptyState(
                    icon: Icons.notifications_none,
                    message: l10n.t('noNotificationsYet'),
                  ),
                ),
              );
            }
            _markDisplayedRead(
              items.where((item) => item.isUnread).map((item) => item.id),
            );
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + 1,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Text(
                    l10n.t('notificationTargetedFeed'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }
                final item = items[index - 1];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      item.isUnread
                          ? Icons.notification_important
                          : Icons.notifications_none,
                    ),
                    title: Text(item.title),
                    subtitle: Text(item.message),
                  ),
                );
              },
            );
          },
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppRecoverableError(message: appErrorMessage(l10n, error)),
            ),
          ),
          loading: () => const AppLoadingSkeleton(),
        ),
      ),
    );
  }
}
