import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/session_restore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _FakeCallableClient implements CallableClient {
  _FakeCallableClient({
    this.workspaceId,
    this.created = false,
    this.setupCompleted = true,
    this.error,
  });

  final String? workspaceId;
  final bool created;
  final bool setupCompleted;
  final Exception? error;
  int callCount = 0;
  String? lastFunctionName;

  @override
  Future<T> call<T>({
    required String functionName,
    required Map<String, dynamic> payload,
    required T Function(dynamic result) parseResult,
    required String defaultErrorMessage,
    String? httpFunctionName,
  }) async {
    callCount += 1;
    lastFunctionName = functionName;
    if (error != null) {
      throw error!;
    }
    return parseResult({
      'workspaceId': workspaceId,
      'created': created,
      'setupCompleted': setupCompleted,
    });
  }
}

class _FakeTelemetry implements AppTelemetry {
  final List<String> events = [];
  final List<String> errorReasons = [];

  @override
  Future<void> log(
    String event, [
    Map<String, Object?> details = const {},
  ]) async {
    events.add(event);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    bool fatal = false,
  }) async {
    errorReasons.add(reason);
  }

  @override
  Future<T> trace<T>(
    String event,
    Future<T> Function() operation, {
    Map<String, Object?> details = const {},
  }) {
    return operation();
  }
}

void main() {
  group('SessionRestoreService', () {
    late _MockFirebaseAuth auth;
    late _MockUser user;
    late FakeFirebaseFirestore firestore;
    late _FakeTelemetry telemetry;

    setUp(() {
      auth = _MockFirebaseAuth();
      user = _MockUser();
      firestore = FakeFirebaseFirestore();
      telemetry = _FakeTelemetry();

      when(() => auth.currentUser).thenReturn(user);
      when(() => user.uid).thenReturn('user_1');
      when(() => auth.signOut()).thenAnswer((_) async {});
    });

    test(
      'restores workspace from membership before bootstrap fallback',
      () async {
        final callable = _FakeCallableClient(workspaceId: 'workspace_boot');
        await firestore.collection('memberships').doc('membership_1').set({
          'userId': 'user_1',
          'workspaceId': 'workspace_1',
        });

        final service = SessionRestoreService(
          auth: auth,
          firestore: firestore,
          callableClient: callable,
          telemetry: telemetry,
        );

        final result = await service.restore();

        expect(result, isNotNull);
        expect(result!.workspaceId, 'workspace_1');
        expect(result.setupCompleted, true);
        expect(callable.callCount, 0);
        expect(telemetry.events, contains('session_restore.success'));
        expect(
          (await firestore.collection('users').doc('user_1').get()).exists,
          isFalse,
        );
      },
    );

    test(
      'falls back to bootstrap when membership and user doc are empty',
      () async {
        final callable = _FakeCallableClient(
          workspaceId: 'workspace_boot',
          created: true,
          setupCompleted: false,
        );

        final service = SessionRestoreService(
          auth: auth,
          firestore: firestore,
          callableClient: callable,
          telemetry: telemetry,
        );

        final result = await service.restore();

        expect(result, isNotNull);
        expect(result!.workspaceId, 'workspace_boot');
        expect(result.setupCompleted, false);
        expect(callable.callCount, 1);
        expect(callable.lastFunctionName, 'ensureUserWorkspaceBootstrap');
        expect(telemetry.events, contains('session_restore.success'));
      },
    );

    test('prefers user workspace over membership query ordering', () async {
      final callable = _FakeCallableClient(workspaceId: 'workspace_boot');
      await firestore.collection('memberships').doc('membership_1').set({
        'userId': 'user_1',
        'workspaceId': 'workspace_2',
      });
      await firestore.collection('users').doc('user_1').set({
        'workspaceId': 'workspace_1',
      });
      await firestore.collection('workspaces').doc('workspace_1').set({
        'ownerId': 'user_1',
      });

      final service = SessionRestoreService(
        auth: auth,
        firestore: firestore,
        callableClient: callable,
        telemetry: telemetry,
      );

      final result = await service.restore();

      expect(result, isNotNull);
      expect(result!.workspaceId, 'workspace_1');
      expect(callable.callCount, 0);
      expect(
        (await firestore
                .collection('memberships')
                .doc('workspace_1_user_1')
                .get())
            .exists,
        isTrue,
      );
    });

    test(
      'chooses a stable workspace when multiple memberships exist',
      () async {
        final callable = _FakeCallableClient(workspaceId: 'workspace_boot');
        await firestore.collection('memberships').doc('membership_b').set({
          'userId': 'user_1',
          'workspaceId': 'workspace_b',
        });
        await firestore.collection('memberships').doc('membership_a').set({
          'userId': 'user_1',
          'workspaceId': 'workspace_a',
        });

        final service = SessionRestoreService(
          auth: auth,
          firestore: firestore,
          callableClient: callable,
          telemetry: telemetry,
        );

        final result = await service.restore();

        expect(result, isNotNull);
        expect(result!.workspaceId, 'workspace_a');
        expect(callable.callCount, 0);
      },
    );

    test(
      'returns null when bootstrap fails after local resolution misses',
      () async {
        final callable = _FakeCallableClient(
          error: const CallableClientException(
            'Failed to restore your workspace.',
            code: 'failed-precondition',
          ),
        );

        final service = SessionRestoreService(
          auth: auth,
          firestore: firestore,
          callableClient: callable,
          telemetry: telemetry,
        );

        final result = await service.restore();

        expect(result, isNull);
        expect(callable.callCount, 1);
        expect(telemetry.errorReasons, contains('session_restore.bootstrap'));
        expect(telemetry.events, contains('session_restore.no_workspace'));
      },
    );

    test(
      'signs the user out when no workspace can be resolved, so the router '
      'does not bounce them between splash and login forever',
      () async {
        final callable = _FakeCallableClient(
          error: const CallableClientException(
            'Failed to restore your workspace.',
            code: 'failed-precondition',
          ),
        );

        final service = SessionRestoreService(
          auth: auth,
          firestore: firestore,
          callableClient: callable,
          telemetry: telemetry,
        );

        final result = await service.restore();

        expect(result, isNull);
        verify(() => auth.signOut()).called(1);
      },
    );
  });
}
