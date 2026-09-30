import 'dart:convert';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockAppCheck extends Mock implements FirebaseAppCheck {}

class _MockTelemetry extends Mock implements AppTelemetry {}

const _config = BackendConfig(
  apiBaseUrl: 'https://api.example.com/',
  syncUrl: 'https://sync.example.com',
);

class _Tokens {
  int idTokenCalls = 0;
  final forcedRefreshes = <bool>[];

  Future<String?> idToken({required bool forceRefresh}) async {
    idTokenCalls++;
    forcedRefreshes.add(forceRefresh);
    return 'id-token-$idTokenCalls';
  }

  Future<String?> appCheckToken() async => 'app-check-token';
}

SelfHostedRpcTransport _transport(MockClient client, _Tokens tokens) {
  return SelfHostedRpcTransport(
    config: _config,
    httpClient: client,
    idToken: tokens.idToken,
    appCheckToken: tokens.appCheckToken,
  );
}

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'sends the {data} envelope with auth, App Check and idempotency headers',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _json(200, {
          'result': {'id': 'expense_1'},
        });
      });

      final result = await _transport(client, _Tokens()).call(
        functionName: 'createExpenseWithQuota',
        payload: {'amount': 100, 'notes': 'حديد'},
        idempotencyKey: 'action_42',
        defaultErrorMessage: 'Could not save.',
      );

      expect(result, {'id': 'expense_1'});
      expect(
        captured.url.toString(),
        'https://api.example.com/v1/rpc/createExpenseWithQuota',
      );
      expect(captured.headers['Authorization'], 'Bearer id-token-1');
      expect(captured.headers['X-Firebase-AppCheck'], 'app-check-token');
      expect(captured.headers['X-Idempotency-Key'], 'action_42');
      expect(jsonDecode(captured.body), {
        'data': {'amount': 100, 'notes': 'حديد'},
      });
    },
  );

  test(
    'maps every error envelope to the same CallableClientException',
    () async {
      const codes = [
        'invalid-argument',
        'failed-precondition',
        'permission-denied',
        'not-found',
        'already-exists',
        'resource-exhausted',
        'internal',
        'unavailable',
      ];
      for (final code in codes) {
        final client = MockClient(
          (_) async => _json(412, {
            'error': {'code': code, 'message': 'Server says $code'},
          }),
        );
        await expectLater(
          _transport(client, _Tokens()).call(
            functionName: 'fn',
            payload: const {},
            idempotencyKey: 'k',
            defaultErrorMessage: 'fallback',
          ),
          throwsA(
            isA<CallableClientException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.message, 'message', 'Server says $code'),
          ),
        );
      }
    },
  );

  test('401 refreshes the ID token and retries exactly once', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return _json(401, {
          'error': {'code': 'unauthenticated', 'message': 'expired'},
        });
      }
      return _json(200, {'result': 'ok'});
    });
    final tokens = _Tokens();

    final result = await _transport(client, tokens).call(
      functionName: 'fn',
      payload: const {},
      idempotencyKey: 'k',
      defaultErrorMessage: 'fallback',
    );

    expect(result, 'ok');
    expect(calls, 2);
    expect(tokens.forcedRefreshes, [false, true]);
  });

  test('a second 401 surfaces unauthenticated instead of looping', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return _json(401, {
        'error': {
          'code': 'unauthenticated',
          'message': 'Please sign in to continue.',
        },
      });
    });

    await expectLater(
      _transport(client, _Tokens()).call(
        functionName: 'fn',
        payload: const {},
        idempotencyKey: 'k',
        defaultErrorMessage: 'fallback',
      ),
      throwsA(
        isA<CallableClientException>().having(
          (e) => e.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
    expect(calls, 2);
  });

  test(
    'missing ID token fails fast as unauthenticated without a request',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _json(200, {'result': null});
      });
      final transport = SelfHostedRpcTransport(
        config: _config,
        httpClient: client,
        idToken: ({required bool forceRefresh}) async => null,
        appCheckToken: () async => null,
      );

      await expectLater(
        transport.call(
          functionName: 'fn',
          payload: const {},
          idempotencyKey: 'k',
          defaultErrorMessage: 'fallback',
        ),
        throwsA(
          isA<CallableClientException>().having(
            (e) => e.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  test(
    'non-JSON or empty bodies become a readable error with the HTTP code',
    () async {
      final client = MockClient(
        (_) async => http.Response('<html>502</html>', 502),
      );

      await expectLater(
        _transport(client, _Tokens()).call(
          functionName: 'fn',
          payload: const {},
          idempotencyKey: 'k',
          defaultErrorMessage: 'Could not save.',
        ),
        throwsA(
          isA<CallableClientException>().having(
            (e) => e.code,
            'code',
            'http-502',
          ),
        ),
      );
    },
  );

  test(
    'network failure maps to unavailable so the offline queue retries',
    () async {
      final client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );

      await expectLater(
        _transport(client, _Tokens()).call(
          functionName: 'fn',
          payload: const {},
          idempotencyKey: 'k',
          defaultErrorMessage: 'fallback',
        ),
        throwsA(
          isA<CallableClientException>().having(
            (e) => e.code,
            'code',
            'unavailable',
          ),
        ),
      );
    },
  );

  test(
    'CallableClient routes through the self-hosted transport when configured',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _json(200, {
          'result': {'workspaceId': 'ws_1'},
        });
      });
      final telemetry = _MockTelemetry();
      when(() => telemetry.log(any(), any())).thenAnswer((_) async {});
      final functions = _MockFunctions();
      final callable = CallableClient(
        functions,
        _MockAuth(),
        _MockAppCheck(),
        telemetry,
        selfHostedTransport: _transport(client, _Tokens()),
      );

      final workspaceId = await callable.call<String>(
        functionName: 'ensureUserWorkspaceBootstrap',
        payload: const {},
        parseResult: (result) => '${(result as Map)['workspaceId']}',
        defaultErrorMessage: 'fallback',
        idempotencyKey: 'action_7',
      );

      expect(workspaceId, 'ws_1');
      expect(captured.headers['X-Idempotency-Key'], 'action_7');
      verifyZeroInteractions(functions);
    },
  );

  test(
    'CallableClient generates an idempotency key when none is given',
    () async {
      final keys = <String?>[];
      final client = MockClient((request) async {
        keys.add(request.headers['X-Idempotency-Key']);
        return _json(200, {'result': null});
      });
      final telemetry = _MockTelemetry();
      when(() => telemetry.log(any(), any())).thenAnswer((_) async {});
      final callable = CallableClient(
        _MockFunctions(),
        _MockAuth(),
        _MockAppCheck(),
        telemetry,
        selfHostedTransport: _transport(client, _Tokens()),
      );

      for (var i = 0; i < 2; i++) {
        await callable.call<void>(
          functionName: 'updateUserSettings',
          payload: const {},
          parseResult: (_) {},
          defaultErrorMessage: 'fallback',
        );
      }

      expect(keys, hasLength(2));
      expect(keys.every((k) => k != null && k.isNotEmpty), isTrue);
      expect(
        keys.first,
        isNot(keys.last),
        reason: 'each direct call gets its own key',
      );
    },
  );
}
