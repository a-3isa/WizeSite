import 'dart:convert';

import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/core/sync/doc_source.dart';
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

/// Settings read from the local replica (cached in [_prefsBox] for a cold
/// start) and written through the queued `updateUserSettings` RPC (spec 004).
class LocalUserSettingsRepository implements UserSettingsRepository {
  LocalUserSettingsRepository(
    this._source,
    this._prefsBox,
    this._mutationService,
  );

  final DocSource _source;
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
      final data = (await _source.getDoc('users', userId))?.data;
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
    yield* _source.watchDoc('users', userId).map((doc) {
      final data = doc?.data ?? const <String, dynamic>{};
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
  return LocalUserSettingsRepository(
    ref.watch(docSourceProvider),
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
