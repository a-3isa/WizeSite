import 'dart:async';
import 'dart:convert';

import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class CallableClient {
  const CallableClient(this._functions, this._auth, this._appCheck);

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseAppCheck _appCheck;

  Future<T> call<T>({
    required String functionName,
    required Map<String, dynamic> payload,
    required T Function(dynamic result) parseResult,
    required String defaultErrorMessage,
    String? httpFunctionName,
  }) async {
    final currentUser = await _authenticatedUser();
    if (currentUser == null) {
      throw const CallableClientException(
        'Please sign in to continue.',
        code: 'unauthenticated',
      );
    }

    await _refreshCallableSession(currentUser, functionName);

    try {
      final response = await _functions
          .httpsCallable(functionName)
          .call<Map<String, dynamic>>(payload);
      return parseResult(response.data);
    } on FirebaseFunctionsException catch (error) {
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
          final response = await _functions
              .httpsCallable(functionName)
              .call<Map<String, dynamic>>(payload);
          return parseResult(response.data);
        } on FirebaseFunctionsException catch (retryError) {
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
    final tokenUpdate = _auth.idTokenChanges().skip(1).firstWhere(
      (candidate) => candidate?.uid == user.uid,
    );

    await user.getIdToken(true);
    String? appCheckToken;
    try {
      appCheckToken = await _appCheck.getToken(true);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('$functionName App Check refresh failed: $error');
      }
    }

    if (kDebugMode) {
      debugPrint(
        '$functionName session refresh: '
        'user=${user.uid}, '
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
        debugPrint('$functionName HTTP App Check fetch failed: $error');
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

final callableClientProvider = Provider<CallableClient>((ref) {
  return CallableClient(
    ref.watch(functionsProvider),
    ref.watch(firebaseAuthProvider),
    FirebaseAppCheck.instance,
  );
});
