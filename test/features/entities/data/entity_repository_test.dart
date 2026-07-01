import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedDirectory(FakeFirebaseFirestore firestore) async {
  Future<void> add(
    String id,
    String type,
    String name,
    String normalized, {
    String? lastUsedAt,
  }) {
    final data = <String, Object?>{
      'id': id,
      'workspaceId': 'ws',
      'name': name,
      'normalizedName': normalized,
      'type': type,
      'createdAt': DateTime.utc(2026, 5, 1).toIso8601String(),
    };
    if (lastUsedAt != null) {
      data['lastUsedAt'] = lastUsedAt;
    }
    return firestore.collection('entities').doc(id).set(data);
  }

  await add(
    'c_a',
    'contractor',
    'Alpha Co',
    'alpha co',
    lastUsedAt: DateTime.utc(2026, 6, 3).toIso8601String(),
  );
  await add(
    'c_b',
    'contractor',
    'Bravo Co',
    'bravo co',
    lastUsedAt: DateTime.utc(2026, 6, 1).toIso8601String(),
  );
  await add(
    'c_c',
    'contractor',
    'Charlie Co',
    'charlie co',
    lastUsedAt: DateTime.utc(2026, 6, 5).toIso8601String(),
  );
  // Legacy contractor with no lastUsedAt (pre-backfill).
  await add('c_legacy', 'contractor', 'Zeta Legacy', 'zeta legacy');
  // Different type, must never appear in a contractor directory.
  await add(
    'e_x',
    'equipment',
    'Crane',
    'crane',
    lastUsedAt: DateTime.utc(2026, 6, 4).toIso8601String(),
  );
}

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

    test('creates updates and hard deletes typed resource profiles', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseEntityRepository(firestore);

      final created = await repository.createEntity(
        workspaceId: 'workspace_1',
        name: 'Crane Crew',
        type: 'equipmentProvider',
        defaultRate: 450,
        rateUnit: 'day',
        phoneNumber: '0100',
        notes: 'Crawler crane',
      );

      expect(created.name, 'Crane Crew');
      expect(created.defaultRate, 450);
      expect(created.rateUnit, 'day');

      final updated = await repository.updateEntity(
        entityId: created.id,
        name: 'Crane Crew Updated',
        type: 'equipmentProvider',
        defaultRate: 500,
        rateUnit: 'hour',
        phoneNumber: '0111',
        notes: 'Updated note',
      );

      expect(updated.name, 'Crane Crew Updated');
      expect(updated.defaultRate, 500);
      expect(updated.rateUnit, 'hour');
      expect(updated.phoneNumber, '0111');

      await repository.deleteEntity(created.id);
      final deleted = await firestore
          .collection('entities')
          .doc(created.id)
          .get();
      expect(deleted.exists, isFalse);
    });
  });

  group('entity directory paging (exact type)', () {
    test('recent sort orders by lastUsedAt within the exact type', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseEntityRepository(firestore);
      await _seedDirectory(firestore);

      final page = await repository.fetchEntityDirectoryPage(
        'ws',
        type: 'contractor',
      );
      final ids = page.items.map((e) => e.id).toList();

      // Newest lastUsedAt first; equipment is excluded.
      expect(ids, containsAllInOrder(['c_c', 'c_a', 'c_b']));
      expect(ids, isNot(contains('e_x')));
    });

    test(
      'name sort returns all of the type (including legacy) alphabetically',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = FirebaseEntityRepository(firestore);
        await _seedDirectory(firestore);

        final page = await repository.fetchEntityDirectoryPage(
          'ws',
          type: 'contractor',
          sort: EntityDirectorySort.name,
        );

        expect(page.items.map((e) => e.id), ['c_a', 'c_b', 'c_c', 'c_legacy']);
      },
    );

    test('id sort orders by document id', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseEntityRepository(firestore);
      await _seedDirectory(firestore);

      final page = await repository.fetchEntityDirectoryPage(
        'ws',
        type: 'contractor',
        sort: EntityDirectorySort.id,
      );

      expect(page.items.map((e) => e.id), ['c_a', 'c_b', 'c_c', 'c_legacy']);
    });

    test('paginates with a stable cursor', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseEntityRepository(firestore);
      await _seedDirectory(firestore);

      final first = await repository.fetchEntityDirectoryPage(
        'ws',
        type: 'contractor',
        sort: EntityDirectorySort.id,
        pageSize: 2,
      );
      expect(first.items.map((e) => e.id), ['c_a', 'c_b']);
      expect(first.hasMore, isTrue);
      expect(first.nextCursor, isNotNull);

      final second = await repository.fetchEntityDirectoryPage(
        'ws',
        type: 'contractor',
        sort: EntityDirectorySort.id,
        pageSize: 2,
        cursor: first.nextCursor,
      );
      expect(second.items.map((e) => e.id), ['c_c', 'c_legacy']);
    });

    test(
      'backfilled legacy entity becomes visible in the recent sort',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = FirebaseEntityRepository(firestore);
        await _seedDirectory(firestore);

        // Simulate the lastUsedAt backfill for the legacy contractor.
        await firestore.collection('entities').doc('c_legacy').set({
          'lastUsedAt': DateTime.utc(2026, 6, 9).toIso8601String(),
        }, SetOptions(merge: true));

        final page = await repository.fetchEntityDirectoryPage(
          'ws',
          type: 'contractor',
        );

        expect(page.items.first.id, 'c_legacy');
      },
    );
  });
}
