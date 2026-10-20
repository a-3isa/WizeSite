import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/utils/local_date_key.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_proposal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Result of "Organize with AI" (contracts/rpc-expense-items.md §3).
class ExpenseTextOrganizeResult {
  const ExpenseTextOrganizeResult({
    required this.text,
    required this.proposal,
    required this.source,
  });

  /// The pasted text as the server used it (trimmed); stored as the
  /// expense transcript (FR-018).
  final String text;
  final ExpenseProposal proposal;

  /// `llm`, or `rules` when the AI failed and the fallback was used.
  final String source;
}

/// Calls `organizeExpenseText`. Online only: an AI proposal must be reviewed
/// by the user right away, so this is never put in the offline queue.
class ExpenseTextOrganizer {
  const ExpenseTextOrganizer(this._client);

  final CallableClient _client;

  /// Throws [CallableClientException] unchanged.
  Future<ExpenseTextOrganizeResult> organize({
    required String workspaceId,
    required String text,
    required String currency,
  }) {
    return _client.call<ExpenseTextOrganizeResult>(
      functionName: 'organizeExpenseText',
      payload: {
        'workspaceId': workspaceId,
        'text': text,
        'currency': currency,
        'today': localDateKey(DateTime.now()),
      },
      parseResult: (result) {
        final map = Map<String, dynamic>.from(result as Map);
        final proposal = map['proposal'];
        return ExpenseTextOrganizeResult(
          text: '${map['text'] ?? text}',
          proposal: proposal is Map
              ? ExpenseProposal.fromMap(Map<String, dynamic>.from(proposal))
              : const ExpenseProposal(),
          source: '${map['source'] ?? 'llm'}',
        );
      },
      defaultErrorMessage: 'Failed to organize the receipt text.',
      // One key per attempt: a network retry of the same request reuses the
      // first AI result instead of paying twice (the RPC is idempotent).
      idempotencyKey: 'organize:${const Uuid().v4()}',
      timeout: const Duration(seconds: 70),
    );
  }
}

final expenseTextOrganizerProvider = Provider<ExpenseTextOrganizer>((ref) {
  return ExpenseTextOrganizer(ref.watch(callableClientProvider));
});
