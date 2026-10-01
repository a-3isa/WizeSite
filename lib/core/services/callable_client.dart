import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Calls the server's RPCs (spec 004, contracts/rpc-api.md) with telemetry.
class CallableClient {
  const CallableClient(this._transport, this._telemetry);

  final SelfHostedRpcTransport _transport;
  final AppTelemetry _telemetry;

  /// [idempotencyKey] makes a mutating call safe to retry: the server applies
  /// it once. The offline queue passes its action id; direct calls get a fresh
  /// key. [timeout] overrides the transport's default for slow calls.
  Future<T> call<T>({
    required String functionName,
    required Map<String, dynamic> payload,
    required T Function(dynamic result) parseResult,
    required String defaultErrorMessage,
    String? idempotencyKey,
    Duration? timeout,
  }) async {
    try {
      await _telemetry.log('callable.request', {'function': functionName});
      final result = await _transport.call(
        functionName: functionName,
        payload: payload,
        idempotencyKey: idempotencyKey ?? const Uuid().v4(),
        defaultErrorMessage: defaultErrorMessage,
        timeout: timeout,
      );
      await _telemetry.log('callable.success', {'function': functionName});
      return parseResult(result);
    } on CallableClientException catch (error) {
      await _telemetry.log('callable.error', {
        'function': functionName,
        'code': error.code ?? 'unknown',
      });
      if (error.code != 'unauthenticated' && error.code != 'unavailable') {
        await _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'callable.$functionName',
        );
      }
      rethrow;
    }
  }
}

class CallableClientException implements Exception {
  const CallableClientException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// The API transport (RPCs and file uploads), signed with the Firebase ID
/// token and App Check token.
final selfHostedRpcTransportProvider = Provider<SelfHostedRpcTransport>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return SelfHostedRpcTransport(
    config: BackendConfig.fromEnvironment,
    httpClient: http.Client(),
    idToken: ({required bool forceRefresh}) async =>
        auth.currentUser?.getIdToken(forceRefresh),
    appCheckToken: () => FirebaseAppCheck.instance.getToken(),
  );
});

final callableClientProvider = Provider<CallableClient>((ref) {
  return CallableClient(
    ref.watch(selfHostedRpcTransportProvider),
    ref.watch(appTelemetryProvider),
  );
});
