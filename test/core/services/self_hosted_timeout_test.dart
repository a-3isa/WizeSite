import 'dart:convert';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A slow function (processVoiceExpense: up to 120 s on the server) can take
/// longer than the default client timeout (spec 004, T083).
void main() {
  SelfHostedRpcTransport transport(Duration serverDelay) =>
      SelfHostedRpcTransport(
        config: const BackendConfig(
          apiBaseUrl: 'https://api.example.com',
          syncUrl: 'https://sync.example.com',
        ),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(serverDelay);
          return http.Response(
            jsonEncode({
              'result': {'ok': true},
            }),
            200,
          );
        }),
        idToken: ({required bool forceRefresh}) async => 'id-token',
        appCheckToken: () async => 'app-check',
        timeout: const Duration(milliseconds: 50),
      );

  test('the default timeout applies when no override is given', () async {
    await expectLater(
      transport(const Duration(milliseconds: 200)).call(
        functionName: 'processVoiceExpense',
        payload: const {},
        idempotencyKey: 'k',
        defaultErrorMessage: 'x',
      ),
      throwsA(
        isA<CallableClientException>().having(
          (e) => e.code,
          'code',
          'deadline-exceeded',
        ),
      ),
    );
  });

  test('a per-call timeout lets a slow function finish', () async {
    final result = await transport(const Duration(milliseconds: 200)).call(
      functionName: 'processVoiceExpense',
      payload: const {},
      idempotencyKey: 'k',
      defaultErrorMessage: 'x',
      timeout: const Duration(seconds: 5),
    );
    expect(result, {'ok': true});
  });
}
