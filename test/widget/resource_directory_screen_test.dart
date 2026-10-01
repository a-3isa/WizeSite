import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:buildtrack_app/features/entities/presentation/screens/resource_directory_screen.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'resource directory paginates, searches, and opens detail route',
    (tester) async {
      final repository = _FakeEntityRepository(
        pages: [
          FirestorePage(items: [_entity('c1', 'Alpha Build')], hasMore: true),
          FirestorePage(items: [_entity('c2', 'Bravo Build')], hasMore: false),
        ],
        searchResults: [_entity('c2', 'Bravo Build')],
      );
      final router = GoRouter(
        initialLocation: AppRoutes.contractorsDirectory,
        routes: [
          GoRoute(
            path: AppRoutes.contractorsDirectory,
            builder: (_, _) => const ResourceDirectoryScreen(
              type: ResourceDirectoryType.contractor,
            ),
          ),
          GoRoute(
            path: AppRoutes.contractors,
            builder: (_, state) => Text('detail:${state.pathParameters['id']}'),
          ),
        ],
      );

      await _pump(tester, repository: repository, router: router);
      await tester.pumpAndSettle();

      expect(find.text('Alpha Build'), findsOneWidget);
      expect(find.text('Bravo Build'), findsNothing);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Bravo Build'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bravo');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repository.searchCalls.single.$2, 'bravo');
      await tester.tap(find.text('Bravo Build'));
      await tester.pumpAndSettle();
      expect(find.text('detail:c2'), findsOneWidget);
    },
  );

  testWidgets('authorized accounting role sees access-gated totals', (
    tester,
  ) async {
    final repository = _FakeEntityRepository(
      pages: [
        FirestorePage(items: [_entity('c1', 'Alpha Build')], hasMore: false),
      ],
    );
    final router = GoRouter(
      initialLocation: AppRoutes.contractorsDirectory,
      routes: [
        GoRoute(
          path: AppRoutes.contractorsDirectory,
          builder: (_, _) => const ResourceDirectoryScreen(
            type: ResourceDirectoryType.contractor,
          ),
        ),
      ],
    );

    await _pump(
      tester,
      repository: repository,
      router: router,
      summaries: [
        EntitySummary(
          entityId: 'c1',
          entityName: 'Alpha Build',
          entityType: 'contractor',
          totalExpenses: 100,
          totalPayments: 25,
          transactionCount: 2,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha Build'), findsOneWidget);
    expect(find.textContaining('100 EGP'), findsOneWidget);
    expect(find.textContaining('25 EGP'), findsOneWidget);
    expect(find.textContaining('-75 EGP'), findsOneWidget);
  });

  testWidgets(
    'denied accounting role sees directory without financial totals',
    (tester) async {
      final repository = _FakeEntityRepository(
        pages: [
          FirestorePage(
            items: [_entity('e1', 'Crane Rentals', type: 'equipmentProvider')],
            hasMore: false,
          ),
        ],
      );
      final router = GoRouter(
        initialLocation: AppRoutes.equipmentDirectory,
        routes: [
          GoRoute(
            path: AppRoutes.equipmentDirectory,
            builder: (_, _) => const ResourceDirectoryScreen(
              type: ResourceDirectoryType.equipment,
            ),
          ),
        ],
      );

      await _pump(
        tester,
        repository: repository,
        router: router,
        role: AccountingAccessRoleType.member,
      );
      await tester.pumpAndSettle();

      expect(find.text('Crane Rentals'), findsOneWidget);
      expect(find.textContaining('EGP'), findsNothing);
      expect(
        find.textContaining('paid amount', findRichText: true),
        findsNothing,
      );
    },
  );

  testWidgets('resource directory exposes add edit and delete actions', (
    tester,
  ) async {
    final repository = _FakeEntityRepository(
      pages: [
        FirestorePage(items: [_entity('c1', 'Alpha Build')], hasMore: false),
      ],
    );
    final router = GoRouter(
      initialLocation: AppRoutes.contractorsDirectory,
      routes: [
        GoRoute(
          path: AppRoutes.contractorsDirectory,
          builder: (_, _) => const ResourceDirectoryScreen(
            type: ResourceDirectoryType.contractor,
          ),
        ),
      ],
    );

    await _pump(tester, repository: repository, router: router);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa_resource_add')), findsOneWidget);
    expect(find.byKey(const Key('qa_resource_actions_c1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa_resource_actions_c1')));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('resource directory debounces search input', (tester) async {
    final repository = _FakeEntityRepository(
      pages: [
        FirestorePage(items: [_entity('c1', 'Alpha Build')], hasMore: false),
      ],
      searchResults: [_entity('c2', 'Bravo Build')],
    );
    final router = GoRouter(
      initialLocation: AppRoutes.contractorsDirectory,
      routes: [
        GoRoute(
          path: AppRoutes.contractorsDirectory,
          builder: (_, _) => const ResourceDirectoryScreen(
            type: ResourceDirectoryType.contractor,
          ),
        ),
      ],
    );

    await _pump(tester, repository: repository, router: router);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'b');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.enterText(find.byType(TextField), 'br');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.enterText(find.byType(TextField), 'bra');
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.searchCalls, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.searchCalls.single.$2, 'bra');
  });
}

AppEntity _entity(String id, String name, {String type = 'contractor'}) =>
    AppEntity(
      id: id,
      workspaceId: 'workspace_1',
      name: name,
      normalizedName: LocalEntityRepository.normalizeName(name),
      type: type,
      createdAt: DateTime.utc(2026, 6, 1),
      lastUsedAt: DateTime.utc(2026, 6, 10),
    );

Future<void> _pump(
  WidgetTester tester, {
  required _FakeEntityRepository repository,
  required GoRouter router,
  AccountingAccessRoleType role = AccountingAccessRoleType.owner,
  List<EntitySummary> summaries = const [],
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
        activeUserIdProvider.overrideWith((ref) => 'user_1'),
        currentAccountingRoleProvider.overrideWith((ref) => Stream.value(role)),
        entityRepositoryProvider.overrideWithValue(repository),
        entityAggregationsProvider.overrideWith(
          (ref, workspaceId) => Stream.value(summaries),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
}

class _FakeEntityRepository implements EntityRepository {
  _FakeEntityRepository({required this.pages, this.searchResults = const []});

  final List<FirestorePage<AppEntity>> pages;
  final List<AppEntity> searchResults;
  final List<(String, String)> searchCalls = [];
  int _pageIndex = 0;

  @override
  Future<FirestorePage<AppEntity>> fetchEntityDirectoryPage(
    String workspaceId, {
    required String type,
    EntityDirectorySort sort = EntityDirectorySort.recent,
    Object? cursor,
    int pageSize = 20,
  }) async {
    final page = pages[_pageIndex];
    if (_pageIndex < pages.length - 1) _pageIndex += 1;
    return page;
  }

  @override
  Future<List<AppEntity>> searchEntities(
    String workspaceId,
    String query, {
    String? type,
    int limit = 20,
  }) async {
    searchCalls.add((workspaceId, query));
    return searchResults;
  }

  @override
  Stream<List<AppEntity>> watchEntities(
    String workspaceId, {
    String? type,
    int limit = 20,
  }) => const Stream.empty();

  @override
  Future<AppEntity?> ensureEntity({
    required String workspaceId,
    required String name,
    String? type,
  }) async => null;

  @override
  Future<AppEntity> createEntity({
    required String workspaceId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  }) async {
    return AppEntity(
      id: 'created',
      workspaceId: workspaceId,
      name: name,
      normalizedName: name.toLowerCase(),
      type: type,
      createdAt: DateTime(2026),
      defaultRate: defaultRate,
      rateUnit: rateUnit ?? '',
      phoneNumber: phoneNumber ?? '',
      notes: notes ?? '',
    );
  }

  @override
  Future<AppEntity> updateEntity({
    required String entityId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  }) async {
    return AppEntity(
      id: entityId,
      workspaceId: 'workspace_1',
      name: name,
      normalizedName: name.toLowerCase(),
      type: type,
      createdAt: DateTime(2026),
      defaultRate: defaultRate,
      rateUnit: rateUnit ?? '',
      phoneNumber: phoneNumber ?? '',
      notes: notes ?? '',
    );
  }

  @override
  Future<void> deleteEntity(String entityId) async {}

  @override
  Future<AppEntity?> getEntityById(String entityId) async => null;

  @override
  Future<AppEntity?> getEntityByName(
    String workspaceId,
    String name, {
    String? type,
  }) async => null;

  @override
  Future<void> saveAttachments({
    required String entityId,
    required List<Map<String, dynamic>> attachments,
  }) async {}
}
