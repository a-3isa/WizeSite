import 'package:buildtrack_app/core/services/pending_id_remap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rewrites a queued child expense onto the server project id', () {
    final remapped = remapPendingProjectId(
      payload: {
        'workspaceId': 'workspace_1',
        'projectId': 'pending_action-1',
        'amount': 40,
      },
      pendingId: 'pending_action-1',
      serverId: 'project_server',
    );

    expect(remapped['projectId'], 'project_server');
    expect(remapped['amount'], 40);
  });

  test('rewrites previousProjectId alongside projectId', () {
    final remapped = remapPendingProjectId(
      payload: {
        'projectId': 'pending_action-1',
        'previousProjectId': 'pending_action-1',
      },
      pendingId: 'pending_action-1',
      serverId: 'project_server',
    );

    expect(remapped['projectId'], 'project_server');
    expect(remapped['previousProjectId'], 'project_server');
  });

  test('leaves unrelated payloads unchanged', () {
    const payload = {
      'workspaceId': 'workspace_1',
      'projectId': 'project_live',
      'amount': 40,
    };

    expect(
      remapPendingProjectId(
        payload: payload,
        pendingId: 'pending_action-1',
        serverId: 'project_server',
      ),
      payload,
    );
  });
}
