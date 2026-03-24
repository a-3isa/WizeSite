import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class CloudFunctionService {
  const CloudFunctionService(this._functions, this._auth, this._appCheck);

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseAppCheck _appCheck;

  Future<Map<String, dynamic>> processVoiceExpense({
    required String storagePath,
    required List<Map<String, String>> projects,
    required String currency,
    required String languageHint,
  }) async {
    final currentUser = await _authenticatedUser();
    if (currentUser == null) {
      throw const CloudFunctionServiceException(
        'Please sign in to continue.',
        code: 'unauthenticated',
      );
    }

    await _refreshCallableSession(currentUser);

    try {
      return await _callProcessVoiceExpense(
        storagePath: storagePath,
        projects: projects,
        currency: currency,
        languageHint: languageHint,
      );
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated') {
        final refreshedUser = await _authenticatedUser();
        if (refreshedUser == null) {
          throw const CloudFunctionServiceException(
            'Please sign in to continue.',
            code: 'unauthenticated',
          );
        }

        await _refreshCallableSession(refreshedUser);

        try {
          return await _callProcessVoiceExpense(
            storagePath: storagePath,
            projects: projects,
            currency: currency,
            languageHint: languageHint,
          );
        } on FirebaseFunctionsException catch (retryError) {
          if (retryError.code == 'unauthenticated') {
            return _callProcessVoiceExpenseOverHttp(
              storagePath: storagePath,
              projects: projects,
              currency: currency,
              languageHint: languageHint,
            );
          }
          throw CloudFunctionServiceException(
            retryError.message ?? 'Failed to process voice expense.',
            code: retryError.code,
          );
        }
      }

      throw CloudFunctionServiceException(
        error.message ?? 'Failed to process voice expense.',
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

  Future<void> _refreshCallableSession(User user) async {
    final tokenUpdate = _auth.idTokenChanges().skip(1).firstWhere(
      (candidate) => candidate?.uid == user.uid,
    );

    await user.getIdToken(true);
    String? appCheckToken;
    try {
      appCheckToken = await _appCheck.getToken(true);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Voice App Check refresh failed: $error');
      }
    }

    if (kDebugMode) {
      debugPrint(
        'Voice callable session refresh: '
        'user=${user.uid}, '
        'appCheckReady=${appCheckToken != null && appCheckToken.isNotEmpty}',
      );
    }

    try {
      await tokenUpdate.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // The Functions plugin sometimes lags behind token refresh on Android.
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<Map<String, dynamic>> _callProcessVoiceExpense({
    required String storagePath,
    required List<Map<String, String>> projects,
    required String currency,
    required String languageHint,
  }) async {
    final callable = _functions.httpsCallable('processVoiceExpense');
    final response = await callable.call<Map<String, dynamic>>({
      'storagePath': storagePath,
      'projects': projects,
      'currency': currency,
      'languageHint': languageHint,
    });

    return response.data;
  }

  Future<Map<String, dynamic>> _callProcessVoiceExpenseOverHttp({
    required String storagePath,
    required List<Map<String, String>> projects,
    required String currency,
    required String languageHint,
  }) async {
    final user = await _authenticatedUser();
    if (user == null) {
      throw const CloudFunctionServiceException(
        'Please sign in to continue.',
        code: 'unauthenticated',
      );
    }

    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw const CloudFunctionServiceException(
        'Authentication is active, but Cloud Functions could not verify the session. Please sign out and sign in again.',
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
        debugPrint('Voice HTTP App Check fetch failed: $error');
      }
    }

    final projectId = Firebase.app().options.projectId;
    final url = Uri.parse(
      'https://us-central1-$projectId.cloudfunctions.net/processVoiceExpenseHttp',
    );
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({
        'storagePath': storagePath,
        'projects': projects,
        'currency': currency,
        'languageHint': languageHint,
      }),
    );

    final body = response.body.trim();
    if (body.isEmpty) {
      throw CloudFunctionServiceException(
        'Voice processing service returned HTTP ${response.statusCode}.',
        code: 'http-${response.statusCode}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw CloudFunctionServiceException(
        'Voice processing service returned an unexpected response (HTTP ${response.statusCode}).',
        code: 'unexpected-response',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const CloudFunctionServiceException(
        'Voice processing service returned an unexpected response.',
        code: 'unexpected-response',
      );
    }

    final result = decoded['result'];
    if (result is Map<String, dynamic>) {
      return result;
    }

    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      final code = '${error['code'] ?? 'unknown'}'.trim();
      final message =
          '${error['message'] ?? 'Failed to process voice expense.'}'.trim();
      throw CloudFunctionServiceException(
        message.isEmpty ? 'Failed to process voice expense.' : message,
        code: code.isEmpty ? 'unknown' : code,
      );
    }

    throw CloudFunctionServiceException(
      'Voice processing service returned HTTP ${response.statusCode}.',
      code: 'http-${response.statusCode}',
    );
  }
}

class CloudFunctionServiceException implements Exception {
  const CloudFunctionServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

final cloudFunctionServiceProvider = Provider<CloudFunctionService>((ref) {
  return CloudFunctionService(
    ref.watch(functionsProvider),
    ref.watch(firebaseAuthProvider),
    FirebaseAppCheck.instance,
  );
});
