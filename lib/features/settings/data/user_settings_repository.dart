import 'dart:convert';

import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

abstract interface class UserSettingsRepository {
  Stream<UserSettings> watchSettings(String userId, {String? fallbackEmail});
  Future<UserSettings> getSettings(String userId, {String? fallbackEmail});
  Future<void> updateCurrency(String userId, String currency);
  Future<void> updateRiskAlerts(String userId, bool enabled);
  Future<void> cacheProfileUpdate({
    required String userId,
    required String fullName,
    String? photoUrl,
  });
}

class FirebaseUserSettingsRepository implements UserSettingsRepository {
  FirebaseUserSettingsRepository(
    this._firestore,
    this._prefsBox,
    this._mutationService,
  );

  final FirebaseFirestore _firestore;
  final Box<String> _prefsBox;
  final WorkspaceMutationService _mutationService;

  String _cacheKey(String userId) => 'user_settings_$userId';

  UserSettings _cachedSettings(String userId, {String fallbackEmail = ''}) {
    final raw = _prefsBox.get(_cacheKey(userId));
    if (raw == null || raw.isEmpty) {
      return UserSettings.defaults(userId: userId, email: fallbackEmail);
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return UserSettings.fromMap(userId, decoded);
  }

  Future<void> _cache(UserSettings settings) async {
    await _prefsBox.put(
      _cacheKey(settings.userId),
      jsonEncode(settings.toMap()),
    );
  }

  @override
  Future<UserSettings> getSettings(
    String userId, {
    String? fallbackEmail,
  }) async {
    try {
      final snap = await _firestore.collection('users').doc(userId).get();
      final data = snap.data();
      if (data == null) {
        return _cachedSettings(userId, fallbackEmail: fallbackEmail ?? '');
      }
      final settings = UserSettings.fromMap(userId, data);
      await _cache(settings);
      return settings;
    } catch (_) {
      return _cachedSettings(userId, fallbackEmail: fallbackEmail ?? '');
    }
  }

  @override
  Stream<UserSettings> watchSettings(
    String userId, {
    String? fallbackEmail,
  }) async* {
    yield _cachedSettings(userId, fallbackEmail: fallbackEmail ?? '');
    yield* _firestore.collection('users').doc(userId).snapshots().map((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      final settings = UserSettings.fromMap(
        userId,
        data,
      ).copyWith(email: (data['email'] as String?) ?? fallbackEmail ?? '');
      _cache(settings);
      return settings;
    });
  }

  @override
  Future<void> updateCurrency(String userId, String currency) async {
    final current = await getSettings(userId);
    final next = current.copyWith(defaultCurrency: currency);
    await _cache(next);
    await _firestore.collection('users').doc(userId).set({
      'defaultCurrency': currency,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _mutationService.updateUserSettings(
      userId: userId,
      defaultCurrency: currency,
    );
  }

  @override
  Future<void> updateRiskAlerts(String userId, bool enabled) async {
    final current = await getSettings(userId);
    final next = current.copyWith(riskAlertsEnabled: enabled);
    await _cache(next);
    await _firestore.collection('users').doc(userId).set({
      'riskAlertsEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _mutationService.updateUserSettings(
      userId: userId,
      riskAlertsEnabled: enabled,
    );
  }

  @override
  Future<void> cacheProfileUpdate({
    required String userId,
    required String fullName,
    String? photoUrl,
  }) async {
    final current = await getSettings(userId);
    await _cache(current.copyWith(fullName: fullName, photoUrl: photoUrl));
  }
}

final userSettingsRepositoryProvider = Provider<UserSettingsRepository>((ref) {
  return FirebaseUserSettingsRepository(
    ref.watch(firestoreProvider),
    Hive.box<String>('app_prefs'),
    ref.watch(workspaceMutationServiceProvider),
  );
});

final currentUserSettingsProvider = StreamProvider<UserSettings>((ref) {
  final userId = ref.watch(activeUserIdProvider);
  final authUser = ref.watch(firebaseAuthProvider).currentUser;
  if (userId == null || userId.isEmpty) {
    return Stream.value(
      UserSettings.defaults(
        userId: authUser?.uid ?? '',
        email: authUser?.email ?? '',
      ),
    );
  }
  return ref
      .watch(userSettingsRepositoryProvider)
      .watchSettings(userId, fallbackEmail: authUser?.email ?? '');
});
