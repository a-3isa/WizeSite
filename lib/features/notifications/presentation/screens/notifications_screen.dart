import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationItemsProvider = StreamProvider((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final userId = ref.watch(activeUserIdProvider);
  if (workspaceId == null ||
      workspaceId.isEmpty ||
      userId == null ||
      userId.isEmpty) {
    return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
  }
  return ref
      .watch(firestoreProvider)
      .collection('notifications')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('targetUserId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots();
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          data: (snap) {
            if (snap.docs.isEmpty) {
              return Center(child: Text(l10n.t('noNotificationsYet')));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: snap.docs.length + 1,
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
                final item = snap.docs[index - 1].data();
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.notification_important),
                    title: Text(item['title'] as String? ?? ''),
                    subtitle: Text(item['message'] as String? ?? ''),
                  ),
                );
              },
            );
          },
          error: (error, _) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
