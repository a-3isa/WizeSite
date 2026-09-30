import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/notifications/data/notification_providers.dart';
import 'package:buildtrack_app/features/notifications/domain/notification_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

  Future<void> _markAllRead(List<NotificationItem> items) async {
    final ids = items.where((item) => item.isUnread).map((item) => item.id);
    await ref.read(notificationRepositoryProvider).markRead(ids);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final locale = Localizations.localeOf(context).languageCode;
    final notificationsAsync = ref.watch(notificationItemsProvider);
    final loadedItems = notificationsAsync.value ?? const [];
    final hasUnread = loadedItems.any((item) => item.isUnread);

    return AppBackScope(
      fallbackRoute: AppRoutes.dashboard,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('notificationsTitle'),
          fallbackRoute: AppRoutes.dashboard,
          actions: [
            TextButton(
              key: const Key('qa_notifications_mark_all_read'),
              onPressed: hasUnread ? () => _markAllRead(loadedItems) : null,
              child: Text(l10n.t('markAllRead')),
            ),
          ],
        ),
        body: notificationsAsync.whenStale(
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

            final cutoff = DateTime.now().subtract(const Duration(days: 7));
            final thisWeek = items
                .where((item) => item.createdAt.isAfter(cutoff))
                .toList(growable: false);
            final earlier = items
                .where((item) => !item.createdAt.isAfter(cutoff))
                .toList(growable: false);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.t('notificationTargetedFeed'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                _NotificationGroup(
                  label: l10n.t('thisWeek'),
                  items: thisWeek,
                  locale: locale,
                ),
                _NotificationGroup(
                  label: l10n.t('earlier'),
                  items: earlier,
                  locale: locale,
                ),
              ],
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

class _NotificationGroup extends StatelessWidget {
  const _NotificationGroup({
    required this.label,
    required this.items,
    required this.locale,
  });

  final String label;
  final List<NotificationItem> items;
  final String locale;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
        ),
        for (final item in items) _NotificationCard(item: item, locale: locale),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.locale});

  final NotificationItem item;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BuildCard(
      margin: const EdgeInsetsDirectional.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6, end: 12),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.isUnread ? t.accent : Colors.transparent,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat.MMMd(locale).format(item.createdAt),
                      style: TextStyle(fontSize: 12, color: t.textFaint),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  style: TextStyle(fontSize: 13.5, color: t.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
