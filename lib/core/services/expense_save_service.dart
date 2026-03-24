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

class ExpenseSaveService {
  const ExpenseSaveService(this._functions, this._auth, this._appCheck);

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseAppCheck _appCheck;

  Future<String?> saveVoiceExpense({
    required String workspaceId,
    required String projectId,
    required String projectName,
    required double amount,
    required String currency,
    required String category,
    required DateTime date,
    required String notes,
    required String transcript,
    required String source,
    required String storagePath,
  }) async {
    final currentUser = await _authenticatedUser();
    if (currentUser == null) {
      throw const ExpenseSaveServiceException(
        'Please sign in to continue.',
        code: 'unauthenticated',
      );
    }

    await _refreshCallableSession(currentUser);

    try {
      return await _callCreateExpenseWithQuota(
        workspaceId: workspaceId,
        projectId: projectId,
        projectName: projectName,
        amount: amount,
        currency: currency,
        category: category,
        date: date,
        notes: notes,
        transcript: transcript,
        source: source,
        storagePath: storagePath,
      );
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated') {
        final refreshedUser = await _authenticatedUser();
        if (refreshedUser == null) {
          throw const ExpenseSaveServiceException(
            'Please sign in to continue.',
            code: 'unauthenticated',
          );
        }

        await _refreshCallableSession(refreshedUser);

        try {
          return await _callCreateExpenseWithQuota(
            workspaceId: workspaceId,
            projectId: projectId,
            projectName: projectName,
            amount: amount,
            currency: currency,
            category: category,
            date: date,
            notes: notes,
            transcript: transcript,
            source: source,
            storagePath: storagePath,
          );
        } on FirebaseFunctionsException catch (retryError) {
          if (retryError.code == 'unauthenticated') {
            return _callCreateExpenseWithQuotaOverHttp(
              workspaceId: workspaceId,
              projectId: projectId,
              projectName: projectName,
              amount: amount,
              currency: currency,
              category: category,
              date: date,
              notes: notes,
              transcript: transcript,
              source: source,
              storagePath: storagePath,
            );
          }
          throw ExpenseSaveServiceException(
            retryError.message ?? 'Failed to save expense.',
            code: retryError.code,
          );
        }
      }

      throw ExpenseSaveServiceException(
        error.message ?? 'Failed to save expense.',
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
        debugPrint('Expense save App Check refresh failed: $error');
      }
    }

    if (kDebugMode) {
      debugPrint(
        'Expense save session refresh: '
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

  Future<String?> _callCreateExpenseWithQuota({
    required String workspaceId,
    required String projectId,
    required String projectName,
    required double amount,
    required String currency,
    required String category,
    required DateTime date,
    required String notes,
    required String transcript,
    required String source,
    required String storagePath,
  }) async {
    final callable = _functions.httpsCallable('createExpenseWithQuota');
    final response = await callable.call<Map<String, dynamic>>({
      'workspaceId': workspaceId,
      'projectId': projectId,
      'projectName': projectName,
      'category': category,
      'amount': amount,
      'currency': currency,
      'date': date.toIso8601String(),
      'notes': notes,
      'supplierName': '',
      'paymentMethod': '',
      'inputMethod': 'voice',
      'transcript': transcript,
      'source': source,
      'storagePath': storagePath,
    });

    return response.data['id'] as String?;
  }

  Future<String?> _callCreateExpenseWithQuotaOverHttp({
    required String workspaceId,
    required String projectId,
    required String projectName,
    required double amount,
    required String currency,
    required String category,
    required DateTime date,
    required String notes,
    required String transcript,
    required String source,
    required String storagePath,
  }) async {
    final user = await _authenticatedUser();
    if (user == null) {
      throw const ExpenseSaveServiceException(
        'Please sign in to continue.',
        code: 'unauthenticated',
      );
    }

    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw const ExpenseSaveServiceException(
        'Authentication is active, but saving could not verify the session. Please sign out and sign in again.',
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
        debugPrint('Expense save HTTP App Check fetch failed: $error');
      }
    }

    final projectIdValue = Firebase.app().options.projectId;
    final url = Uri.parse(
      'https://us-central1-$projectIdValue.cloudfunctions.net/createExpenseWithQuotaHttp',
    );
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({
        'workspaceId': workspaceId,
        'projectId': projectId,
        'projectName': projectName,
        'category': category,
        'amount': amount,
        'currency': currency,
        'date': date.toIso8601String(),
        'notes': notes,
        'supplierName': '',
        'paymentMethod': '',
        'inputMethod': 'voice',
        'transcript': transcript,
        'source': source,
        'storagePath': storagePath,
      }),
    );

    final body = response.body.trim();
    if (body.isEmpty) {
      throw ExpenseSaveServiceException(
        'Expense save service returned HTTP ${response.statusCode}.',
        code: 'http-${response.statusCode}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ExpenseSaveServiceException(
        'Expense save service returned an unexpected response (HTTP ${response.statusCode}).',
        code: 'unexpected-response',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const ExpenseSaveServiceException(
        'Expense save service returned an unexpected response.',
        code: 'unexpected-response',
      );
    }

    final result = decoded['result'];
    if (result is Map<String, dynamic>) {
      return result['id'] as String?;
    }

    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      final code = '${error['code'] ?? 'unknown'}'.trim();
      final message =
          '${error['message'] ?? 'Failed to save expense.'}'.trim();
      throw ExpenseSaveServiceException(
        message.isEmpty ? 'Failed to save expense.' : message,
        code: code.isEmpty ? 'unknown' : code,
      );
    }

    throw ExpenseSaveServiceException(
      'Expense save service returned HTTP ${response.statusCode}.',
      code: 'http-${response.statusCode}',
    );
  }
}

class ExpenseSaveServiceException implements Exception {
  const ExpenseSaveServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

final expenseSaveServiceProvider = Provider<ExpenseSaveService>((ref) {
  return ExpenseSaveService(
    ref.watch(functionsProvider),
    ref.watch(firebaseAuthProvider),
    FirebaseAppCheck.instance,
  );
});
