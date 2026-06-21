import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:buildtrack_app/features/entities/presentation/widgets/entity_autocomplete_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
}

class _FakeEntityRepository implements EntityRepository {
  const _FakeEntityRepository(this.entities);

  final List<AppEntity> entities;

  @override
  Future<FirestorePage<AppEntity>> fetchEntityDirectoryPage(
    String workspaceId, {
    required String type,
    EntityDirectorySort sort = EntityDirectorySort.recent,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    final items = entities
        .where((entity) => entity.workspaceId == workspaceId)
        .where((entity) => entity.type == type)
        .take(pageSize)
        .toList(growable: false);
    return FirestorePage(items: items, hasMore: false);
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
    final normalized = FirebaseEntityRepository.normalizeName(query);
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
