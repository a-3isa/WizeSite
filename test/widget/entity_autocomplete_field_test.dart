import 'dart:async';

import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:buildtrack_app/features/entities/presentation/widgets/entity_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows recent suggestions and selects an entity', (tester) async {
    final repository = _FakeEntityRepository([
      AppEntity(
        id: 'recent',
        workspaceId: 'workspace_1',
        name: 'Steel Recent',
        normalizedName: 'steel recent',
        type: 'supplier',
        createdAt: DateTime.utc(2026, 5, 1),
        lastUsedAt: DateTime.utc(2026, 5, 20),
      ),
      AppEntity(
        id: 'old',
        workspaceId: 'workspace_1',
        name: 'Steel Old',
        normalizedName: 'steel old',
        type: 'supplier',
        createdAt: DateTime.utc(2026, 5, 1),
        lastUsedAt: DateTime.utc(2026, 5, 2),
      ),
    ]);
    String? selectedId;
    String? selectedName;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [entityRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: EntityAutocompleteField(
              workspaceId: 'workspace_1',
              entityType: 'supplier',
              label: 'Supplier',
              onChanged: (id, name) {
                selectedId = id;
                selectedName = name;
              },
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'steel');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Steel Recent'), findsOneWidget);
    expect(find.text('Steel Old'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Steel Recent')).dy,
      lessThan(tester.getTopLeft(find.text('Steel Old')).dy),
    );

    await tester.tap(find.text('Steel Recent'));
    await tester.pumpAndSettle();

    expect(selectedId, 'recent');
    expect(selectedName, 'Steel Recent');
    expect(find.text('Steel Old'), findsNothing);
  });

  testWidgets('ignores stale suggestions when a slower search completes late', (
    tester,
  ) async {
    final repository = _ControlledSearchEntityRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [entityRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: EntityAutocompleteField(
              workspaceId: 'workspace_1',
              entityType: 'supplier',
              label: 'Supplier',
              onChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'st');
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.queries, ['st']);

    await tester.enterText(find.byType(TextField), 'steel');
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.queries, ['st', 'steel']);

    repository.complete('steel', [_entity(id: 'latest', name: 'Steel Latest')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Steel Latest'), findsOneWidget);
    expect(find.text('Steel Stale'), findsNothing);

    repository.complete('st', [_entity(id: 'stale', name: 'Steel Stale')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Steel Latest'), findsOneWidget);
    expect(find.text('Steel Stale'), findsNothing);
  });
}

AppEntity _entity({required String id, required String name}) {
  return AppEntity(
    id: id,
    workspaceId: 'workspace_1',
    name: name,
    normalizedName: name.toLowerCase(),
    type: 'supplier',
    createdAt: DateTime.utc(2026, 5, 1),
  );
}

class _FakeEntityRepository implements EntityRepository {
  const _FakeEntityRepository(this.entities);

  final List<AppEntity> entities;

  @override
  Future<RecordPage<AppEntity>> fetchEntityDirectoryPage(
    String workspaceId, {
    required String type,
    EntityDirectorySort sort = EntityDirectorySort.recent,
    Object? cursor,
    int pageSize = 20,
  }) async {
    final items = entities
        .where((entity) => entity.workspaceId == workspaceId)
        .where((entity) => entity.type == type)
        .take(pageSize)
        .toList(growable: false);
    return RecordPage(items: items, hasMore: false);
  }

  @override
  Future<AppEntity?> ensureEntity({
    required String workspaceId,
    required String name,
    String? type,
  }) async {
    return null;
  }

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
  Future<AppEntity?> getEntityById(String entityId) async {
    for (final entity in entities) {
      if (entity.id == entityId) {
        return entity;
      }
    }
    return null;
  }

  @override
  Future<AppEntity?> getEntityByName(
    String workspaceId,
    String name, {
    String? type,
  }) async {
    return null;
  }

  @override
  Future<List<AppEntity>> searchEntities(
    String workspaceId,
    String query, {
    String? type,
    int limit = 20,
  }) async {
    final normalized = LocalEntityRepository.normalizeName(query);
    return entities
        .where((entity) => entity.workspaceId == workspaceId)
        .where((entity) => type == null || entity.type == type)
        .where((entity) => entity.normalizedName.startsWith(normalized))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> saveAttachments({
    required String entityId,
    required List<Map<String, dynamic>> attachments,
  }) async {}

  @override
  Stream<List<AppEntity>> watchEntities(
    String workspaceId, {
    String? type,
    int limit = 20,
  }) {
    return Stream.value(entities.take(limit).toList(growable: false));
  }
}

class _ControlledSearchEntityRepository extends _FakeEntityRepository {
  _ControlledSearchEntityRepository() : super(const []);

  final List<String> queries = [];
  final Map<String, Completer<List<AppEntity>>> _pending = {};

  @override
  Future<List<AppEntity>> searchEntities(
    String workspaceId,
    String query, {
    String? type,
    int limit = 20,
  }) {
    queries.add(query);
    final completer = Completer<List<AppEntity>>();
    _pending[query] = completer;
    return completer.future;
  }

  void complete(String query, List<AppEntity> results) {
    _pending.remove(query)?.complete(results);
  }
}
