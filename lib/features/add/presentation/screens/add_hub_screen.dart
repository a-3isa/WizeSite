import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AddHubScreen extends StatelessWidget {
  const AddHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('quickAdd'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActionCard(
            icon: Icons.receipt_long,
            title: l10n.t('addExpense'),
            subtitle: l10n.t('addExpenseSubtitle'),
            onTap: () => context.push(AppRoutes.addExpense),
          ),
          _ActionCard(
            icon: Icons.list,
            title: l10n.t('expenseList'),
            subtitle: l10n.t('expenseListSubtitle'),
            onTap: () => context.push(AppRoutes.expenses),
          ),
          _ActionCard(
            icon: Icons.payments,
            title: l10n.t('addPayment'),
            subtitle: l10n.t('addPaymentSubtitle'),
            onTap: () => context.push(AppRoutes.addPayment),
          ),
          _ActionCard(
            icon: Icons.list_alt,
            title: l10n.t('paymentList'),
            subtitle: l10n.t('paymentListSubtitle'),
            onTap: () => context.push(AppRoutes.payments),
          ),
          _ActionCard(
            icon: Icons.engineering,
            title: l10n.t('addWorkerEntry'),
            subtitle: l10n.t('addWorkerEntrySubtitle'),
            onTap: () => context.push('/worker-entry/new'),
          ),
          _ActionCard(
            icon: Icons.work,
            title: l10n.t('createProject'),
            subtitle: l10n.t('createProjectSubtitle'),
            onTap: () => context.push(AppRoutes.createProject),
          ),
          _ActionCard(
            icon: Icons.mic,
            title: l10n.t('voiceExpense'),
            subtitle: l10n.t('voiceExpenseSubtitle'),
            onTap: () => context.push(AppRoutes.voiceExpense),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
