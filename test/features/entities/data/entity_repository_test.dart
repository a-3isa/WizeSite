import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirebaseEntityRepository', () {
    test('reuses duplicate entities by normalized name and type', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseEntityRepository(firestore);

      await firestore.collection('entities').doc('steel').set({
        'workspaceId': 'workspace_1',
        'name': 'Steel Supplier',
        'normalizedName': 'steel supplier',
        'type': 'supplier',
        'lastUsedAt': DateTime.utc(2026, 5, 1).toIso8601String(),
        'createdAt': DateTime.utc(2026, 4, 1).toIso8601String(),
      });

      final entity = await repository.ensureEntity(
        workspaceId: 'workspace_1',
        name: '  STEEL SUPPLIER  ',
        type: 'supplier',
      );

      final allEntities = await firestore.collection('entities').get();
      expect(entity?.id, 'steel');
      expect(allEntities.docs, hasLength(1));
    });

    test('orders suggestions by lastUsedAt before older matches', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseEntityRepository(firestore);

      await firestore.collection('entities').doc('old').set({
        'workspaceId': 'workspace_1',
        'name': 'Steel Old',
        'normalizedName': 'steel old',
        'type': 'supplier',
        'lastUsedAt': DateTime.utc(2026, 5, 1).toIso8601String(),
        'createdAt': DateTime.utc(2026, 4, 1).toIso8601String(),
      });
      await firestore.collection('entities').doc('recent').set({
        'workspaceId': 'workspace_1',
        'name': 'Steel Recent',
        'normalizedName': 'steel recent',
        'type': 'supplier',
        'lastUsedAt': DateTime.utc(2026, 5, 20).toIso8601String(),
        'createdAt': DateTime.utc(2026, 4, 2).toIso8601String(),
      });

      final matches = await repository.searchEntities(
        'workspace_1',
        'steel',
        type: 'supplier',
      );

      expect(matches.map((entity) => entity.id), ['recent', 'old']);
    });
  });
}
