import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExpenseSaveService {
  const ExpenseSaveService(this._client);

  final CallableClient _client;

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
    try {
      return await _client.call<String?>(
        functionName: 'createExpenseWithQuota',
        httpFunctionName: 'createExpenseWithQuotaHttp',
        payload: {
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
        },
        parseResult: (result) {
          if (result is Map<String, dynamic>) {
            return result['id'] as String?;
          }
          return null;
        },
        defaultErrorMessage: 'Failed to save expense.',
      );
    } on CallableClientException catch (error) {
      throw ExpenseSaveServiceException(error.message, code: error.code);
    }
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
  return ExpenseSaveService(ref.watch(callableClientProvider));
});
