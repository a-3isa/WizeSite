import 'dart:async';
import 'dart:convert';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class CallableClient {
  const CallableClient(
    this._functions,
    this._auth,
    this._appCheck,
    this._telemetry, {
    SelfHostedRpcTransport? selfHostedTransport,
  }) : _selfHosted = selfHostedTransport;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseAppCheck _appCheck;
  final AppTelemetry _telemetry;

  /// Set only in builds with `--dart-define=API_BASE_URL=...` (spec 004).
  final SelfHostedRpcTransport? _selfHosted;

  /// [idempotencyKey] makes a mutating call safe to retry: the self-hosted
  /// backend applies it once. The offline queue passes its action id; direct
  /// calls get a fresh key. Ignored by the Firebase transport.
  Future<T> call<T>({
    required String functionName,
    required Map<String, dynamic> payload,
    required T Function(dynamic result) parseResult,
    required String defaultErrorMessage,
    String? httpFunctionName,
    String? idempotencyKey,
    Duration? selfHostedTimeout,
  }) async {
    final selfHosted = _selfHosted;
    if (selfHosted != null) {
      return _callSelfHosted(
        selfHosted,
        functionName: functionName,
        payload: payload,
        parseResult: parseResult,
        defaultErrorMessage: defaultErrorMessage,
        idempotencyKey: idempotencyKey ?? const Uuid().v4(),
        timeout: selfHostedTimeout,
      );
    }

    final currentUser = await _authenticatedUser();
    if (currentUser == null) {
      throw const CallableClientException(
        'Please sign in to continue.',
        code: 'unauthenticated',
      );
    }

    await _refreshCallableSession(currentUser, functionName);

    try {
      await _telemetry.log('callable.request', {'function': functionName});
      final response = await _functions
          .httpsCallable(functionName)
          .call<Map<String, dynamic>>(payload);
      await _telemetry.log('callable.success', {'function': functionName});
      return parseResult(response.data);
    } on FirebaseFunctionsException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[callable.error] function=$functionName '
          'code=${error.code}',
        );
      }
      await _telemetry.log('callable.error', {
        'function': functionName,
        'code': error.code,
      });
      if (error.code != 'unauthenticated') {
        await _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'callable.$functionName',
        );
      }
      if (error.code == 'unauthenticated') {
        final refreshedUser = await _authenticatedUser();
        if (refreshedUser == null) {
          throw const CallableClientException(
            'Please sign in to continue.',
            code: 'unauthenticated',
          );
        }

        await _refreshCallableSession(refreshedUser, functionName);

        try {
          await _telemetry.log('callable.retry', {'function': functionName});
          final response = await _functions
              .httpsCallable(functionName)
              .call<Map<String, dynamic>>(payload);
          await _telemetry.log('callable.retry_success', {
            'function': functionName,
          });
          return parseResult(response.data);
        } on FirebaseFunctionsException catch (retryError) {
          if (kDebugMode) {
            debugPrint(
              '[callable.retry_error] function=$functionName '
              'code=${retryError.code}',
            );
          }
          await _telemetry.log('callable.retry_error', {
            'function': functionName,
            'code': retryError.code,
          });
          await _telemetry.recordError(
            retryError,
            StackTrace.current,
            reason: 'callable.$functionName.retry',
          );
          if (retryError.code == 'unauthenticated' &&
              httpFunctionName != null &&
              httpFunctionName.isNotEmpty) {
            return _callOverHttp(
              functionName: httpFunctionName,
              payload: payload,
              parseResult: parseResult,
              defaultErrorMessage: defaultErrorMessage,
            );
          }
          throw CallableClientException(
            retryError.message ?? defaultErrorMessage,
            code: retryError.code,
          );
        }
      }

      throw CallableClientException(
        error.message ?? defaultErrorMessage,
        code: error.code,
      );
    }
  }

  Future<T> _callSelfHosted<T>(
    SelfHostedRpcTransport transport, {
    required String functionName,
    required Map<String, dynamic> payload,
    required T Function(dynamic result) parseResult,
    required String defaultErrorMessage,
    required String idempotencyKey,
    Duration? timeout,
  }) async {
    try {
      await _telemetry.log('callable.request', {'function': functionName});
      final result = await transport.call(
        functionName: functionName,
        payload: payload,
        idempotencyKey: idempotencyKey,
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

  Future<User?> _authenticatedUser() async {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      return currentUser;
    }

    try {
      return await _auth
          .authStateChanges()
          .where((user) => user != null)
          .cast<User>()
          .first
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      return null;
    }
  }

  Future<void> _refreshCallableSession(User user, String functionName) async {
    final tokenUpdate = _auth
        .idTokenChanges()
        .skip(1)
        .firstWhere((candidate) => candidate?.uid == user.uid);

    await user.getIdToken(true);
    String? appCheckToken;
    try {
      appCheckToken = await _appCheck.getToken(true);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('$functionName App Check refresh failed');
      }
    }

    if (kDebugMode) {
      debugPrint(
        '$functionName session refresh: '
        'appCheckReady=${appCheckToken != null && appCheckToken.isNotEmpty}',
      );
    }

    try {
      await tokenUpdate.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<T> _callOverHttp<T>({
    required String functionName,
    required Map<String, dynamic> payload,
    required T Function(dynamic result) parseResult,
    required String defaultErrorMessage,
  }) async {
    final user = await _authenticatedUser();
    if (user == null) {
      throw const CallableClientException(
        'Please sign in to continue.',
        code: 'unauthenticated',
      );
    }

    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw const CallableClientException(
        'Authentication is active, but the app could not verify the session. Please sign out and sign in again.',
        code: 'session-sync',
      );
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
    try {
      final appCheckToken = await _appCheck.getToken(false);
      if (appCheckToken != null && appCheckToken.isNotEmpty) {
        headers['X-Firebase-AppCheck'] = appCheckToken;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('$functionName HTTP App Check fetch failed');
      }
    }

    final projectId = Firebase.app().options.projectId;
    final url = Uri.parse(
      'https://us-central1-$projectId.cloudfunctions.net/$functionName',
    );
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode(payload),
    );
    if (kDebugMode) {
      debugPrint(
        '[callable.http] function=$functionName '
        'status=${response.statusCode}',
      );
    }

    final body = response.body.trim();
    if (body.isEmpty) {
      throw CallableClientException(
        '$defaultErrorMessage (HTTP ${response.statusCode}).',
        code: 'http-${response.statusCode}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw CallableClientException(
        '$defaultErrorMessage (unexpected HTTP response).',
        code: 'unexpected-response',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const CallableClientException(
        'Service returned an unexpected response.',
        code: 'unexpected-response',
      );
    }

    final result = decoded['result'];
    if (result != null) {
      return parseResult(result);
    }

    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      final code = '${error['code'] ?? 'unknown'}'.trim();
      final message = '${error['message'] ?? defaultErrorMessage}'.trim();
      throw CallableClientException(
        message.isEmpty ? defaultErrorMessage : message,
        code: code.isEmpty ? 'unknown' : code,
      );
    }

    throw CallableClientException(
      '$defaultErrorMessage (HTTP ${response.statusCode}).',
      code: 'http-${response.statusCode}',
    );
  }
}

class CallableClientException implements Exception {
  const CallableClientException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// The self-hosted API transport (RPCs and file uploads); null in Firebase
/// builds (no `--dart-define=API_BASE_URL`).
final selfHostedRpcTransportProvider = Provider<SelfHostedRpcTransport?>((ref) {
  const backend = BackendConfig.fromEnvironment;
  if (!backend.useSelfHostedBackend) {
    return null;
  }
  final auth = ref.watch(firebaseAuthProvider);
  return SelfHostedRpcTransport(
    config: backend,
    httpClient: http.Client(),
    idToken: ({required bool forceRefresh}) async =>
        auth.currentUser?.getIdToken(forceRefresh),
    appCheckToken: () => FirebaseAppCheck.instance.getToken(),
  );
});

final callableClientProvider = Provider<CallableClient>((ref) {
  return CallableClient(
    ref.watch(functionsProvider),
    ref.watch(firebaseAuthProvider),
    FirebaseAppCheck.instance,
    ref.watch(appTelemetryProvider),
    selfHostedTransport: ref.watch(selfHostedRpcTransportProvider),
  );
});
