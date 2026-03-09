import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AddHubScreen extends StatelessWidget {
  const AddHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Add')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActionCard(
            icon: Icons.receipt_long,
            title: 'Add Expense',
            subtitle: 'Record a new project expense in seconds.',
            onTap: () => context.push(AppRoutes.addExpense),
          ),
          _ActionCard(
            icon: Icons.list,
            title: 'Expense List',
            subtitle: 'View, edit, and archive expenses.',
            onTap: () => context.push(AppRoutes.expenses),
          ),
          _ActionCard(
            icon: Icons.payments,
            title: 'Add Payment',
            subtitle: 'Record client payment and update balance.',
            onTap: () => context.push(AppRoutes.addPayment),
          ),
          _ActionCard(
            icon: Icons.list_alt,
            title: 'Payment List',
            subtitle: 'View, edit, and archive payments.',
            onTap: () => context.push(AppRoutes.payments),
          ),
          _ActionCard(
            icon: Icons.engineering,
            title: 'Add Worker Entry',
            subtitle: 'Capture labor days and auto-calculate cost.',
            onTap: () => context.push('/worker-entry/new'),
          ),
          _ActionCard(
            icon: Icons.work,
            title: 'Create Project',
            subtitle: 'Create a new project with contract details.',
            onTap: () => context.push(AppRoutes.createProject),
          ),
          _ActionCard(
            icon: Icons.mic,
            title: 'Voice Expense',
            subtitle: 'Speak naturally, confirm parsed result, then save.',
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
