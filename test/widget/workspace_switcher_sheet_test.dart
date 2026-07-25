import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/settings/presentation/widgets/workspace_switcher_sheet.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

final _proSubscription = SubscriptionState(
  tier: PlanTier.pro,
  status: SubscriptionStatus.active,
  store: 'test',
  isAutoRenewing: true,
  lastSyncedAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets(
    'entitlement helper matches pro + active/trial/grace, mirroring the server',
    (tester) async {
      expect(workspaceCreationEntitled(_proSubscription), isTrue);
      expect(workspaceCreationEntitled(SubscriptionState.free()), isFalse);
      expect(
        workspaceCreationEntitled(
          SubscriptionState(
            tier: PlanTier.pro,
            status: SubscriptionStatus.expired,
            store: 'test',
            isAutoRenewing: false,
            lastSyncedAt: DateTime(2026, 1, 1),
          ),
        ),
        isFalse,
      );
      expect(
        workspaceCreationEntitled(
          SubscriptionState(
            tier: PlanTier.pro,
            status: SubscriptionStatus.grace,
            store: 'test',
            isAutoRenewing: true,
            lastSyncedAt: DateTime(2026, 1, 1),
          ),
        ),
        isTrue,
        reason:
            'server hasUnlimitedQuota() treats grace as entitled; client must match',
      );
    },
  );

  testWidgets(
    'single-workspace switcher is still tappable and opens the sheet',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
            activeWorkspaceIdProvider.overrideWith((ref) => 'ws_1'),
            userWorkspaceSummariesProvider.overrideWith(
              (ref) => Stream.value(const [
                WorkspaceSummary(
                  id: 'ws_1',
                  name: 'Solo Workspace',
                  role: 'owner',
                  isOwnedByCurrentUser: true,
                ),
              ]),
            ),
            currentSubscriptionStreamProvider.overrideWith(
              (ref) => Stream.value(SubscriptionState.free()),
            ),
          ],
          child: _app(
            const DashboardHeader(projects: [], selectedProject: null),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('qa_workspace_dropdown')));
      await tester.pumpAndSettle();

      expect(find.text('Solo Workspace'), findsWidgets);
      expect(find.byKey(const Key('qa_workspace_create')), findsOneWidget);
    },
  );

  testWidgets(
    'pro workspace can open the create-workspace form from the sheet',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
            activeWorkspaceIdProvider.overrideWith((ref) => 'ws_1'),
            userWorkspaceSummariesProvider.overrideWith(
              (ref) => Stream.value(const [
                WorkspaceSummary(
                  id: 'ws_1',
                  name: 'Pro Workspace',
                  role: 'owner',
                  isOwnedByCurrentUser: true,
                ),
              ]),
            ),
            currentSubscriptionStreamProvider.overrideWith(
              (ref) => Stream.value(_proSubscription),
            ),
          ],
          child: _app(
            const DashboardHeader(projects: [], selectedProject: null),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('qa_workspace_dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('createWorkspaceUpsell'), findsNothing);

      await tester.tap(find.byKey(const Key('qa_workspace_create')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qa_new_workspace_name')), findsOneWidget);
      expect(find.byKey(const Key('qa_new_workspace_save')), findsOneWidget);
    },
  );

  testWidgets('free workspace sees the upgrade upsell in the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          activeWorkspaceIdProvider.overrideWith((ref) => 'ws_1'),
          userWorkspaceSummariesProvider.overrideWith(
            (ref) => Stream.value(const [
              WorkspaceSummary(
                id: 'ws_1',
                name: 'Free Workspace',
                role: 'owner',
                isOwnedByCurrentUser: true,
              ),
            ]),
          ),
          currentSubscriptionStreamProvider.overrideWith(
            (ref) => Stream.value(SubscriptionState.free()),
          ),
        ],
        child: _app(const DashboardHeader(projects: [], selectedProject: null)),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('qa_workspace_dropdown')));
    await tester.pumpAndSettle();

    expect(
      find.text('Upgrade to Pro to create additional workspaces.'),
      findsOneWidget,
    );
  });

  testWidgets('creating a workspace calls the mutation service and switches', (
    tester,
  ) async {
    final workspaceService = _MockWorkspaceMutationService();
    when(
      () => workspaceService.createWorkspace(
        sourceWorkspaceId: 'ws_1',
        workspaceName: 'New Site',
        defaultCurrency: 'EGP',
      ),
    ).thenAnswer((_) async => 'ws_new');

    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        activeWorkspaceIdProvider.overrideWith((ref) => 'ws_1'),
        userWorkspaceSummariesProvider.overrideWith(
          (ref) => Stream.value(const [
            WorkspaceSummary(
              id: 'ws_1',
              name: 'Pro Workspace',
              role: 'owner',
              isOwnedByCurrentUser: true,
            ),
          ]),
        ),
        currentSubscriptionStreamProvider.overrideWith(
          (ref) => Stream.value(_proSubscription),
        ),
        workspaceMutationServiceProvider.overrideWithValue(workspaceService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const DashboardHeader(projects: [], selectedProject: null)),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('qa_workspace_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa_workspace_create')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('qa_new_workspace_name')),
      'New Site',
    );
    await tester.tap(find.byKey(const Key('qa_new_workspace_save')));
    await tester.pumpAndSettle();

    verify(
      () => workspaceService.createWorkspace(
        sourceWorkspaceId: 'ws_1',
        workspaceName: 'New Site',
        defaultCurrency: 'EGP',
      ),
    ).called(1);
    expect(container.read(activeWorkspaceIdProvider), 'ws_new');
  });
}
