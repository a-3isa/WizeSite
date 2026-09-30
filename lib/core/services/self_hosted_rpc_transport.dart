import 'dart:async';
import 'dart:convert';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:http/http.dart' as http;

typedef IdTokenProvider =
    Future<String?> Function({required bool forceRefresh});
typedef AppCheckTokenProvider = Future<String?> Function();

/// HTTP transport for the self-hosted RPC API (contracts/rpc-api.md).
///
/// Sends `{"data": payload}` to `POST /v1/rpc/{functionName}` and maps the
/// `{"error": {code, message}}` envelope to the same [CallableClientException]
/// the Firebase transport throws, so callers, [SyncErrorClassifier] and the
/// offline queue behave identically on either backend.
class SelfHostedRpcTransport {
  SelfHostedRpcTransport({
    required BackendConfig config,
    required http.Client httpClient,
    required IdTokenProvider idToken,
    required AppCheckTokenProvider appCheckToken,
    Duration timeout = const Duration(seconds: 30),
  }) : _config = config,
       _http = httpClient,
       _idToken = idToken,
       _appCheckToken = appCheckToken,
       _timeout = timeout;

  final BackendConfig _config;
  final http.Client _http;
  final IdTokenProvider _idToken;
  final AppCheckTokenProvider _appCheckToken;
  final Duration _timeout;

  Future<dynamic> call({
    required String functionName,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
    required String defaultErrorMessage,
  }) async {
    final first = await _send(
      functionName: functionName,
      payload: payload,
      idempotencyKey: idempotencyKey,
      forceRefresh: false,
    );
    // An expired ID token is the common cause of a 401: refresh once, retry once.
    final response = first.statusCode == 401
        ? await _send(
            functionName: functionName,
            payload: payload,
            idempotencyKey: idempotencyKey,
            forceRefresh: true,
          )
        : first;
    return _decode(response, defaultErrorMessage);
  }

  Future<http.Response> _send({
    required String functionName,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
    required bool forceRefresh,
  }) async {
    final idToken = await _idToken(forceRefresh: forceRefresh);
    if (idToken == null || idToken.isEmpty) {
      throw const CallableClientException(
        'Please sign in to continue.',
        code: 'unauthenticated',
      );
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
      'X-Idempotency-Key': idempotencyKey,
    };
    try {
      final appCheck = await _appCheckToken();
      if (appCheck != null && appCheck.isNotEmpty) {
        headers['X-Firebase-AppCheck'] = appCheck;
      }
    } catch (_) {
      // The server rejects a missing token with `unauthenticated`; surface that.
    }
    try {
      return await _http
          .post(
            _config.rpcUri(functionName),
            headers: headers,
            body: jsonEncode({'data': payload}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const CallableClientException(
        'The server took too long to respond. Please try again.',
        code: 'deadline-exceeded',
      );
    } on http.ClientException {
      throw const CallableClientException(
        'Could not reach the server. Your change will sync when you are back online.',
        code: 'unavailable',
      );
    }
  }

  dynamic _decode(http.Response response, String defaultErrorMessage) {
    final body = utf8.decode(response.bodyBytes).trim();
    Object? decoded;
    if (body.isNotEmpty) {
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        decoded = null;
      }
    }
    if (decoded is Map<String, dynamic>) {
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          decoded.containsKey('result')) {
        return decoded['result'];
      }
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final code = '${error['code'] ?? ''}'.trim();
        final message = '${error['message'] ?? ''}'.trim();
        throw CallableClientException(
          message.isEmpty ? defaultErrorMessage : message,
          code: code.isEmpty ? 'http-${response.statusCode}' : code,
        );
      }
    }
    throw CallableClientException(
      '$defaultErrorMessage (HTTP ${response.statusCode}).',
      code: 'http-${response.statusCode}',
    );
  }
}
