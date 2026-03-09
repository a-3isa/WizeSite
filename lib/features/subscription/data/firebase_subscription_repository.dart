import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FirebaseSubscriptionRepository implements SubscriptionRepository {
  FirebaseSubscriptionRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<SubscriptionState> watchSubscription(String workspaceId) {
    return _firestore
        .collection('subscriptions')
        .doc(workspaceId)
        .snapshots()
        .map(
          (snap) => snap.exists
              ? _fromDocument(snap.data() ?? const {})
              : SubscriptionState.free(),
        );
  }

  @override
  Future<SubscriptionState> getSubscription(String workspaceId) async {
    final snap = await _firestore
        .collection('subscriptions')
        .doc(workspaceId)
        .get();
    if (!snap.exists) {
      return SubscriptionState.free();
    }
    return _fromDocument(snap.data() ?? const {});
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
  final firestore = ref.watch(firestoreProvider);
  return FirebaseSubscriptionRepository(firestore);
});
