import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExpenseSaveService {
  const ExpenseSaveService(this._mutationService);

  final WorkspaceMutationService _mutationService;

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
    final result = await _mutationService.createManualExpense(
      workspaceId: workspaceId,
      projectId: projectId,
      projectName: projectName,
      category: category,
      amount: amount,
      currency: currency,
      date: date,
      notes: notes,
      supplierName: '',
      paymentMethod: '',
      inputMethod: 'voice',
      transcript: transcript,
      source: source,
      storagePath: storagePath,
    );
    return result.id;
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
  return ExpenseSaveService(ref.watch(workspaceMutationServiceProvider));
});
