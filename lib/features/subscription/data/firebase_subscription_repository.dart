import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads the workspace subscription through [DocSource], so it serves both
/// Firebase builds and the local replica (spec 004, tasks.md T051).
class FirebaseSubscriptionRepository implements SubscriptionRepository {
  FirebaseSubscriptionRepository(FirebaseFirestore firestore)
    : _source = FirestoreDocSource(firestore);

  FirebaseSubscriptionRepository.withSource(this._source);

  final DocSource _source;

  @override
  Stream<SubscriptionState> watchSubscription(String workspaceId) {
    return _source
        .watchDoc('subscriptions', workspaceId)
        .map(
          (doc) =>
              doc == null ? SubscriptionState.free() : _fromDocument(doc.data),
        );
  }

  @override
  Future<SubscriptionState> getSubscription(String workspaceId) async {
    final doc = await _source.getDoc('subscriptions', workspaceId);
    return doc == null ? SubscriptionState.free() : _fromDocument(doc.data);
  }

  SubscriptionState _fromDocument(Map<String, dynamic> data) {
    DateTime? toDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    SubscriptionStatus parseStatus(String? raw) {
      return SubscriptionStatus.values.firstWhere(
        (status) => status.name == raw,
        orElse: () => SubscriptionStatus.unknown,
      );
    }

    PlanTier parseTier(String? raw) {
      return PlanTier.values.firstWhere(
        (tier) => tier.name == raw,
        orElse: () => PlanTier.free,
      );
    }

    return SubscriptionState(
      tier: parseTier(data['tier'] as String?),
      status: parseStatus(data['status'] as String?),
      store: data['store'] as String? ?? 'unknown',
      isAutoRenewing: data['isAutoRenewing'] as bool? ?? false,
      lastSyncedAt: toDate(data['lastSyncedAt']) ?? DateTime.now(),
      trialEndsAt: toDate(data['trialEndsAt']),
      periodEndsAt: toDate(data['periodEndsAt']),
    );
  }
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return FirebaseSubscriptionRepository.withSource(
    ref.watch(docSourceProvider),
  );
});
