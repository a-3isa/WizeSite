import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

/// Inline error surface shared by the sign-in, sign-up and reset screens so a
/// failure looks identical wherever it happens.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      key: const Key('qa_auth_error'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.expenseSoft,
        borderRadius: BorderRadius.circular(t.rSm),
        border: Border.all(color: t.expense.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: t.expense, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: t.expense, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline success/info surface (e.g. "reset link sent").
class AuthInfoBanner extends StatelessWidget {
  const AuthInfoBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      key: const Key('qa_auth_info'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.incomeSoft,
        borderRadius: BorderRadius.circular(t.rSm),
        border: Border.all(color: t.income.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: t.income, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: t.income, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
