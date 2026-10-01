/// Session, workspace and notification reads over the local replica
/// (spec 004, T050–T053): the same provider code, fed by [LocalDocSource].
library;

import 'dart:async';

import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/features/notifications/data/notification_repository.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/local_db.dart';

class _MockMutations extends Mock implements WorkspaceMutationService {}

Future<T> _until<T>(
  ProviderContainer container,
  StreamProvider<T> provider,
  bool Function(T value) ready,
) {
  final completer = Completer<T>();
  final sub = container.listen<AsyncValue<T>>(provider, (_, next) {
    final value = next.value;
    if (value != null && ready(value) && !completer.isCompleted) {
      completer.complete(value);
    }
  }, fireImmediately: true);
  addTearDown(sub.close);
  return completer.future.timeout(const Duration(seconds: 5));
}

void main() {
  late LocalTestDb local;
  late LocalDocSource source;

  setUp(() async {
    local = await LocalTestDb.open();
    source = LocalDocSource(Future.value(local.db));
    await local.seedRows('user_profiles', [
      {'id': 'u1', 'active_workspace_id': 'ws_own', 'email': 'a@x.io'},
    ]);
    await local.seedRows('workspaces', [
      {'id': 'ws_own', 'owner_uid': 'u1', 'name': 'موقعي'},
      {'id': 'ws_team', 'owner_uid': 'u2', 'name': 'Team'},
    ]);
    await local.seedRows('memberships', [
      {
        'id': 'ws_team_u1',
        'workspace_id': 'ws_team',
        'user_uid': 'u1',
        'role': 'accountingApproved',
        'status': 'active',
      },
    ]);
    await local.seedRows('notifications', [
      for (final (id, target, created) in [
        ('n1', 'u1', '2026-06-01 00:00:00Z'),
        ('n2', 'u1', '2026-06-03 00:00:00Z'),
        ('n3', 'u2', '2026-06-04 00:00:00Z'),
      ])
        {
          'id': id,
          'workspace_id': 'ws_own',
          'target_user_id': target,
          'title': 'تنبيه $id',
          'message': '',
          'created_at': created,
        },
    ]);
  });
  tearDown(() => local.dispose());

  test('notifications: targeted, newest first', () async {
    final repo = NotificationRepository(source, _MockMutations());
    final items = await repo
        .watchTargeted(workspaceId: 'ws_own', userId: 'u1')
        .first;
    expect(items.map((i) => i.id), ['n2', 'n1']);
    expect(items.first.title, 'تنبيه n2');
  });

  test('workspace providers: preferred id, name and summaries', () async {
    final container = ProviderContainer(
      overrides: [
        docSourceProvider.overrideWithValue(source),
        activeUserIdProvider.overrideWith((ref) => 'u1'),
        activeWorkspaceIdProvider.overrideWith((ref) => 'ws_own'),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await _until(container, userPreferredWorkspaceIdProvider, (_) => true),
      'ws_own',
    );
    expect(
      await _until(container, activeWorkspaceNameProvider, (v) => v.isNotEmpty),
      'موقعي',
    );
    final summaries = await _until(
      container,
      userWorkspaceSummariesProvider,
      (v) => v.length == 2,
    );
    expect(summaries.map((s) => (s.id, s.role, s.isOwnedByCurrentUser)), [
      ('ws_own', 'owner', true),
      ('ws_team', 'accountingApproved', false),
    ]);
  });
}
