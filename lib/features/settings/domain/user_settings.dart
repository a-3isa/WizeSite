class UserSettings {
  const UserSettings({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.photoUrl,
    required this.defaultCurrency,
    required this.riskAlertsEnabled,
    required this.setupCompleted,
  });

  final String userId;
  final String fullName;
  final String email;
  final String photoUrl;
  final String defaultCurrency;
  final bool riskAlertsEnabled;
  final bool setupCompleted;

  factory UserSettings.defaults({required String userId, String email = ''}) {
    return UserSettings(
      userId: userId,
      fullName: '',
      email: email,
      photoUrl: '',
      defaultCurrency: 'EGP',
      riskAlertsEnabled: true,
      setupCompleted: true,
    );
  }

  factory UserSettings.fromMap(String userId, Map<String, dynamic> map) {
    return UserSettings(
      userId: userId,
      fullName: map['fullName'] as String? ?? '',
      email: map['email'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      defaultCurrency: map['defaultCurrency'] as String? ?? 'EGP',
      riskAlertsEnabled: map['riskAlertsEnabled'] as bool? ?? true,
      setupCompleted: map['setupCompleted'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'fullName': fullName,
    'email': email,
    'photoUrl': photoUrl,
    'defaultCurrency': defaultCurrency,
    'riskAlertsEnabled': riskAlertsEnabled,
    'setupCompleted': setupCompleted,
  };

  UserSettings copyWith({
    String? fullName,
    String? email,
    String? photoUrl,
    String? defaultCurrency,
    bool? riskAlertsEnabled,
    bool? setupCompleted,
  }) {
    return UserSettings(
      userId: userId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      riskAlertsEnabled: riskAlertsEnabled ?? this.riskAlertsEnabled,
      setupCompleted: setupCompleted ?? this.setupCompleted,
    );
  }
}
