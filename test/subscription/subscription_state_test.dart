import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionState', () {
    test('fromMap parses tier and status', () {
      final state = SubscriptionState.fromMap({
        'tier': 'pro',
        'status': 'trial',
        'store': 'play_store',
        'isAutoRenewing': true,
        'lastSyncedAt': '2026-03-09T10:00:00.000Z',
        'trialEndsAt': '2026-03-16T10:00:00.000Z',
      });

      expect(state.tier, PlanTier.pro);
      expect(state.status, SubscriptionStatus.trial);
      expect(state.isActiveOrTrial, isTrue);
      expect(state.trial.isInTrial, isTrue);
    });

    test('free factory defaults to expired free', () {
      final state = SubscriptionState.free();
      expect(state.tier, PlanTier.free);
      expect(state.status, SubscriptionStatus.expired);
      expect(state.isPro, isFalse);
    });
  });
}
