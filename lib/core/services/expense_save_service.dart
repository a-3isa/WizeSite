import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExpenseSaveService {
  const ExpenseSaveService(this._functions);

  final FirebaseFunctions _functions;

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
}

final expenseSaveServiceProvider = Provider<ExpenseSaveService>((ref) {
  return ExpenseSaveService(FirebaseFunctions.instance);
});
