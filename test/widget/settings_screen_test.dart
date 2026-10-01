import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/memory_doc_source.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _FakeUserSettingsRepository extends Fake
    implements UserSettingsRepository {
  _FakeUserSettingsRepository({this.failCurrencyUpdates = false});

  final bool failCurrencyUpdates;
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
    if (failCurrencyUpdates) {
      throw Exception('network exploded');
    }
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
        path: '/settings/workspace',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Workspace Route'))),
      ),
      GoRoute(
        path: '/settings/sync',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Sync Status Route'))),
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
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Buildozer',
      packageName: 'com.example.buildozer',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
  });

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
        setupCompleted: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Reads come from the local replica; these tests need none.
            docSourceProvider.overrideWithValue(MemoryDocSource()),
            activeUserIdProvider.overrideWith((ref) => 'user_1'),
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            userWorkspaceSummariesProvider.overrideWith(
              (ref) => Stream.value(const [
                WorkspaceSummary(
                  id: 'workspace_1',
                  name: 'Acme Sites',
                  role: 'owner',
                  isOwnedByCurrentUser: true,
                ),
              ]),
            ),
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
            currentUsageProvider.overrideWith(
              (ref) => Stream.value(
                const UsageSnapshot(
                  periodKey: '202606',
                  activeProjects: 1,
                  expensesCount: 7,
                  paymentsCount: 3,
                  workerEntriesCount: 2,
                  memberCount: 1,
                  limits: PlanLimits(
                    activeProjects: 1,
                    expensesPerMonth: 30,
                    paymentsPerMonth: 30,
                    workerEntriesPerMonth: 30,
                    teamMembers: 1,
                  ),
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Jane Builder'), findsOneWidget);
      expect(find.text('jane@example.com'), findsOneWidget);
      expect(find.text('USD'), findsWidgets);
      expect(find.text('Workspace'), findsWidgets);
      expect(find.text('Acme Sites'), findsOneWidget);
      expect(find.text('Manage Team'), findsNothing);
      expect(find.text('Team Members'), findsNothing);

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

  testWidgets(
    'SettingsScreen exposes expanded currencies and rolls back failed saves',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeSettingsRepository = _FakeUserSettingsRepository(
        failCurrencyUpdates: true,
      );
      final mockAuth = _MockFirebaseAuth();
      final mockUser = _MockUser();

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.displayName).thenReturn('Jane Builder');
      when(() => mockUser.email).thenReturn('jane@example.com');
      when(() => mockUser.photoURL).thenReturn(null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Reads come from the local replica; these tests need none.
            docSourceProvider.overrideWithValue(MemoryDocSource()),
            activeUserIdProvider.overrideWith((ref) => 'user_1'),
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            userWorkspaceSummariesProvider.overrideWith(
              (ref) => Stream.value(const [
                WorkspaceSummary(
                  id: 'workspace_1',
                  name: 'Acme Sites',
                  role: 'owner',
                  isOwnedByCurrentUser: true,
                ),
              ]),
            ),
            firebaseAuthProvider.overrideWithValue(mockAuth),
            localeControllerProvider.overrideWith(
              (ref) => LocaleController(deviceLocale: const Locale('en')),
            ),
            userSettingsRepositoryProvider.overrideWithValue(
              fakeSettingsRepository,
            ),
            currentUserSettingsProvider.overrideWith(
              (ref) => Stream.value(
                const UserSettings(
                  userId: 'user_1',
                  fullName: 'Jane Builder',
                  email: 'jane@example.com',
                  photoUrl: '',
                  defaultCurrency: 'USD',
                  riskAlertsEnabled: true,
                  setupCompleted: true,
                ),
              ),
            ),
            currentSubscriptionStreamProvider.overrideWith(
              (ref) => Stream.value(SubscriptionState.free()),
            ),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byType(BelowDropdownField<String>));
      await tester.pumpAndSettle();

      for (final currency in ['KWD', 'QAR', 'BHD', 'OMR', 'JOD']) {
        expect(find.text(currency), findsOneWidget);
      }

      await tester.tap(find.text('KWD'));
      await tester.pumpAndSettle();

      expect(fakeSettingsRepository.currencyUpdates, ['KWD']);
      expect(find.text('USD'), findsWidgets);
      expect(
        find.text('Could not save settings. Your previous value was restored.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SettingsScreen shows version, help/legal links, and confirms diagnostics',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeSettingsRepository = _FakeUserSettingsRepository();
      final mockAuth = _MockFirebaseAuth();
      final mockUser = _MockUser();

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.displayName).thenReturn('Jane Builder');
      when(() => mockUser.email).thenReturn('jane@example.com');
      when(() => mockUser.photoURL).thenReturn(null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Reads come from the local replica; these tests need none.
            docSourceProvider.overrideWithValue(MemoryDocSource()),
            activeUserIdProvider.overrideWith((ref) => 'user_1'),
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            userWorkspaceSummariesProvider.overrideWith(
              (ref) => Stream.value(const [
                WorkspaceSummary(
                  id: 'workspace_1',
                  name: 'Acme Sites',
                  role: 'owner',
                  isOwnedByCurrentUser: true,
                ),
              ]),
            ),
            firebaseAuthProvider.overrideWithValue(mockAuth),
            localeControllerProvider.overrideWith(
              (ref) => LocaleController(deviceLocale: const Locale('en')),
            ),
            userSettingsRepositoryProvider.overrideWithValue(
              fakeSettingsRepository,
            ),
            currentUserSettingsProvider.overrideWith(
              (ref) => Stream.value(
                UserSettings.defaults(
                  userId: 'user_1',
                  email: 'jane@example.com',
                ),
              ),
            ),
            currentSubscriptionStreamProvider.overrideWith(
              (ref) => Stream.value(SubscriptionState.free()),
            ),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('App version'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('1.2.3 (45)'), findsOneWidget);
      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Run diagnostics'), findsOneWidget);
      expect(find.text('Sync status'), findsOneWidget);

      await tester.tap(find.text('Acme Sites'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Workspace Route'), findsOneWidget);

      GoRouter.of(tester.element(find.text('Workspace Route'))).go('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('Sync status'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Sync Status Route'), findsOneWidget);

      GoRouter.of(
        tester.element(find.text('Sync Status Route')),
      ).go('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('Run diagnostics'));
      await tester.pumpAndSettle();

      expect(find.text('Run diagnostics?'), findsOneWidget);
      expect(
        find.text('This can send a diagnostic report or terminate the app.'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets(
    'SettingsScreen keeps subscription content visible while refreshing',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeSettingsRepository = _FakeUserSettingsRepository();
      final mockAuth = _MockFirebaseAuth();
      final mockUser = _MockUser();
      final refreshKeyProvider = StateProvider<int>((ref) => 0);

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.displayName).thenReturn('Jane Builder');
      when(() => mockUser.email).thenReturn('jane@example.com');
      when(() => mockUser.photoURL).thenReturn(null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Reads come from the local replica; these tests need none.
            docSourceProvider.overrideWithValue(MemoryDocSource()),
            activeUserIdProvider.overrideWith((ref) => 'user_1'),
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            userWorkspaceSummariesProvider.overrideWith(
              (ref) => Stream.value(const [
                WorkspaceSummary(
                  id: 'workspace_1',
                  name: 'Acme Sites',
                  role: 'owner',
                  isOwnedByCurrentUser: true,
                ),
              ]),
            ),
            firebaseAuthProvider.overrideWithValue(mockAuth),
            localeControllerProvider.overrideWith(
              (ref) => LocaleController(deviceLocale: const Locale('en')),
            ),
            userSettingsRepositoryProvider.overrideWithValue(
              fakeSettingsRepository,
            ),
            currentUserSettingsProvider.overrideWith(
              (ref) => Stream.value(
                UserSettings.defaults(
                  userId: 'user_1',
                  email: 'jane@example.com',
                ),
              ),
            ),
            currentUsageProvider.overrideWith(
              (ref) => Stream.value(
                const UsageSnapshot(
                  periodKey: '202606',
                  activeProjects: 1,
                  expensesCount: 7,
                  paymentsCount: 2,
                  workerEntriesCount: 0,
                  memberCount: 1,
                  limits: PlanLimits(
                    activeProjects: 1,
                    expensesPerMonth: 30,
                    paymentsPerMonth: 30,
                    workerEntriesPerMonth: 30,
                    teamMembers: 1,
                  ),
                ),
              ),
            ),
            currentSubscriptionStreamProvider.overrideWith((ref) {
              final key = ref.watch(refreshKeyProvider);
              if (key == 0) {
                return Stream.value(SubscriptionState.free());
              }
              return const Stream<SubscriptionState>.empty();
            }),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Free Plan'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Monthly Usage'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Monthly Usage'), findsOneWidget);
      expect(find.textContaining('7 / 30'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
        listen: false,
      );
      container.read(refreshKeyProvider.notifier).state = 1;
      await tester.pump();

      expect(find.text('Free Plan'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    },
  );
}
