enum PlanTier { free, pro }

enum SubscriptionStatus { trial, active, grace, expired, canceled, unknown }

class TrialState {
  const TrialState({required this.isInTrial, this.trialEndsAt});

  final bool isInTrial;
  final DateTime? trialEndsAt;
}

class SubscriptionState {
  const SubscriptionState({
    required this.tier,
    required this.status,
    required this.store,
    required this.isAutoRenewing,
    required this.lastSyncedAt,
    this.trialEndsAt,
    this.periodEndsAt,
  });

  final PlanTier tier;
  final SubscriptionStatus status;
  final String store;
  final bool isAutoRenewing;
  final DateTime lastSyncedAt;
  final DateTime? trialEndsAt;
  final DateTime? periodEndsAt;

  bool get isPro => tier == PlanTier.pro;
  bool get isActiveOrTrial =>
      status == SubscriptionStatus.active || status == SubscriptionStatus.trial;

  TrialState get trial => TrialState(
    isInTrial: status == SubscriptionStatus.trial,
    trialEndsAt: trialEndsAt,
  );

  Map<String, dynamic> toMap() {
    return {
      'tier': tier.name,
      'status': status.name,
      'store': store,
      'isAutoRenewing': isAutoRenewing,
      'lastSyncedAt': lastSyncedAt.toIso8601String(),
      'trialEndsAt': trialEndsAt?.toIso8601String(),
      'periodEndsAt': periodEndsAt?.toIso8601String(),
    };
  }

  factory SubscriptionState.fromMap(Map<String, dynamic> map) {
    SubscriptionStatus parseStatus(String? raw) {
      return SubscriptionStatus.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => SubscriptionStatus.unknown,
      );
    }

    PlanTier parseTier(String? raw) {
      return PlanTier.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => PlanTier.free,
      );
    }

    return SubscriptionState(
      tier: parseTier(map['tier'] as String?),
      status: parseStatus(map['status'] as String?),
      store: map['store'] as String? ?? 'unknown',
      isAutoRenewing: map['isAutoRenewing'] as bool? ?? false,
      lastSyncedAt:
          DateTime.tryParse(map['lastSyncedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      trialEndsAt: DateTime.tryParse(map['trialEndsAt'] as String? ?? ''),
      periodEndsAt: DateTime.tryParse(map['periodEndsAt'] as String? ?? ''),
    );
  }

  factory SubscriptionState.free() {
    return SubscriptionState(
      tier: PlanTier.free,
      status: SubscriptionStatus.expired,
      store: 'none',
      isAutoRenewing: false,
      lastSyncedAt: DateTime.now(),
    );
  }
}
