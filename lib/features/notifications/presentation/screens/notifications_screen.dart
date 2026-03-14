import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationItemsProvider = StreamProvider((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
  }
  return ref
      .watch(firestoreProvider)
      .collection('notifications')
      .where('workspaceId', isEqualTo: workspaceId)
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('notificationsTitle'))),
      body: notificationsAsync.when(
        data: (snap) {
          if (snap.docs.isEmpty) {
            return Center(child: Text(l10n.t('noNotificationsYet')));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snap.docs.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = snap.docs[index].data();
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
    );
  }
}
