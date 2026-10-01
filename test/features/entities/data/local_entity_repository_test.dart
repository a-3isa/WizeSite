import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/local_db.dart';

class _MockMutations extends Mock implements WorkspaceMutationService {}

void main() {
  late LocalTestDb local;
  late LocalEntityRepository repository;

  Map<String, Object?> entity(
    String id,
    String name, {
    String type = 'supplier',
    String? lastUsed,
    String workspace = 'ws_1',
  }) => {
    'id': id,
    'workspace_id': workspace,
    'type': type,
    'name': name,
    'normalized_name': LocalEntityRepository.normalizeName(name),
    'last_used_at': lastUsed,
    'attachments': '[]',
  };

  setUp(() async {
    local = await LocalTestDb.open();
    repository = LocalEntityRepository(
      Future.value(local.db),
      _MockMutations(),
    );
    await local.seedRows('entities', [
      entity('s1', 'Cement Co', lastUsed: '2026-06-01 00:00:00Z'),
      entity('s2', 'Brick Ltd', lastUsed: '2026-06-03 00:00:00Z'),
      entity('s3', 'Cedar Wood', lastUsed: '2026-06-03 00:00:00Z'),
      entity('s4', 'حديد المدينة', lastUsed: '2026-05-01 00:00:00Z'),
      entity('s_never', 'Never Used'), // no lastUsedAt
      entity(
        'c1',
        'Crew One',
        type: 'contractor',
        lastUsed: '2026-06-09 00:00:00Z',
      ),
      entity(
        'x1',
        'Cement Co',
        workspace: 'ws_2',
        lastUsed: '2026-06-09 00:00:00Z',
      ),
    ]);
  });
  tearDown(() => local.dispose());

  Future<List<String>> allPages(EntityDirectorySort sort) async {
    final ids = <String>[];
    Object? cursor;
    RecordPage<AppEntity> page;
    do {
      page = await repository.fetchEntityDirectoryPage(
        'ws_1',
        type: 'supplier',
        sort: sort,
        pageSize: 2,
        cursor: cursor,
      );
      ids.addAll(page.items.map((e) => e.id));
      cursor = page.nextCursor;
    } while (page.hasMore);
    return ids;
  }

  test(
    'watchEntities: recent first, excludes never-used (like Firestore orderBy)',
    () async {
      final items = await repository
          .watchEntities('ws_1', type: 'supplier')
          .first;
      expect(items.map((e) => e.id), isNot(contains('s_never')));
      expect(items.first.lastUsedAt, DateTime.utc(2026, 6, 3));
    },
  );

  test('directory paging: recent (ties broken by name), name, id', () async {
    expect(await allPages(EntityDirectorySort.recent), [
      's2',
      's3',
      's1',
      's4',
    ]);
    expect(await allPages(EntityDirectorySort.name), [
      's2',
      's3',
      's1',
      's_never',
      's4',
    ]);
    expect(await allPages(EntityDirectorySort.id), [
      's1',
      's2',
      's3',
      's4',
      's_never',
    ]);
  });

  test(
    'search is a prefix match on the normalized name, workspace scoped',
    () async {
      final hits = await repository.searchEntities('ws_1', 'ce');
      expect(hits.map((e) => e.id), unorderedEquals(['s1', 's3']));
      final arabic = await repository.searchEntities('ws_1', 'حديد');
      expect(arabic.single.id, 's4');
      final contractors = await repository.searchEntities(
        'ws_1',
        'c',
        type: 'contractor',
      );
      expect(contractors.single.id, 'c1');
    },
  );

  test('getEntityByName normalizes; getEntityById', () async {
    expect(
      (await repository.getEntityByName('ws_1', '  CEMENT   co '))?.id,
      's1',
    );
    expect((await repository.getEntityById('s2'))?.name, 'Brick Ltd');
    expect(await repository.getEntityById('nope'), isNull);
  });
}
