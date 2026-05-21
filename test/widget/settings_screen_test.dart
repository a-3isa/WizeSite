import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _FakeUserSettingsRepository extends Fake
    implements UserSettingsRepository {
  final List<String> currencyUpdates = [];
  final List<bool> riskAlertUpdates = [];

  @override
  Future<UserSettings> getSettings(
    String userId, {
    String? fallbackEmail,
  }) async {
    return UserSettings.defaults(userId: userId, email: fallbackEmail ?? '');
  }

  @override
  Future<void> updateCurrency(String userId, String currency) async {
    currencyUpdates.add(currency);
  }

  @override
  Future<void> updateRiskAlerts(String userId, bool enabled) async {
    riskAlertUpdates.add(enabled);
  }

  @override
  Future<void> cacheProfileUpdate({
    required String userId,
    required String fullName,
    String? photoUrl,
  }) async {}

  @override
  Stream<UserSettings> watchSettings(String userId, {String? fallbackEmail}) {
    return Stream.value(
      UserSettings.defaults(userId: userId, email: fallbackEmail ?? ''),
    );
  }
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/settings/profile',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/settings/team',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/subscription/plans',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/subscription/manage',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
}

void main() {
  testWidgets(
    'SettingsScreen shows persisted settings and saves currency and risk alerts',
    (tester) async {
      final fakeSettingsRepository = _FakeUserSettingsRepository();
      final mockAuth = _MockFirebaseAuth();
      final mockUser = _MockUser();

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.displayName).thenReturn('Jane Builder');
      when(() => mockUser.email).thenReturn('jane@example.com');
      when(() => mockUser.photoURL).thenReturn(null);

      final settings = UserSettings(
        userId: 'user_1',
        fullName: 'Jane Builder',
        email: 'jane@example.com',
        photoUrl: '',
        defaultCurrency: 'USD',
        riskAlertsEnabled: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeUserIdProvider.overrideWith((ref) => 'user_1'),
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            firebaseAuthProvider.overrideWithValue(mockAuth),
            localeControllerProvider.overrideWith(
              (ref) => LocaleController(deviceLocale: const Locale('en')),
            ),
            userSettingsRepositoryProvider.overrideWithValue(
              fakeSettingsRepository,
            ),
            currentUserSettingsProvider.overrideWith(
              (ref) => Stream.value(settings),
            ),
            currentSubscriptionStreamProvider.overrideWith(
              (ref) => Stream.value(SubscriptionState.free()),
            ),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Jane Builder'), findsOneWidget);
      expect(find.text('jane@example.com'), findsOneWidget);
      expect(find.text('USD'), findsWidgets);

      await tester.tap(find.byType(BelowDropdownField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAR').last);
      await tester.pumpAndSettle();

      expect(fakeSettingsRepository.currencyUpdates, ['SAR']);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(fakeSettingsRepository.riskAlertUpdates, [true]);
    },
  );
}
