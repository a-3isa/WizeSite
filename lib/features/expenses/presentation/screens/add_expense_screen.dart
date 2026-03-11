import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({this.expenseId, super.key});

  final String? expenseId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _supplierController = TextEditingController();
  String _category = 'materials';
  String? _projectId;
  String _projectName = '';
  DateTime _date = DateTime.now();
  bool _loading = false;
  bool _prefilling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.expenseId != null) {
      _prefill();
    }
  }

  Future<void> _prefill() async {
    setState(() => _prefilling = true);
    final expense = await ref
        .read(expenseRepositoryProvider)
        .getExpense(widget.expenseId!);
    if (expense != null && mounted) {
      setState(() {
        _projectId = expense.projectId;
        _projectName = expense.projectName;
        _category = expense.category;
        _amountController.text = expense.amount.toStringAsFixed(2);
        _notesController.text = expense.notes;
        _supplierController.text = expense.supplierName;
        _date = expense.date;
      });
    }
    if (mounted) {
      setState(() => _prefilling = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _supplierController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    final amount = double.tryParse(_amountController.text.trim());
    if (workspaceId == null || userId == null) {
      setState(() => _error = 'Please login first.');
      return;
    }
    if (_projectId == null || amount == null || amount <= 0) {
      setState(() => _error = 'Select project and enter valid amount.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.expenseId == null) {
        await ref
            .read(expenseRepositoryProvider)
            .createExpense(
              workspaceId: workspaceId,
              userId: userId,
              projectId: _projectId!,
              projectName: _projectName,
              category: _category,
              amount: amount,
              currency: 'EGP',
              date: _date,
              notes: _notesController.text.trim(),
              supplierName: _supplierController.text.trim(),
            );
      } else {
        await ref
            .read(expenseRepositoryProvider)
            .updateExpense(
              expenseId: widget.expenseId!,
              category: _category,
              amount: amount,
              date: _date,
              notes: _notesController.text.trim(),
              supplierName: _supplierController.text.trim(),
            );
      }
      if (mounted) {
        context.pop();
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        if (mounted) {
          context.push('${AppRoutes.subscriptionLimit}?limit=expensesPerMonth');
        }
      } else {
        setState(() => _error = e.message ?? e.code);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expenseId == null ? 'Add Expense' : 'Edit Expense'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.voiceExpense),
            icon: const Icon(Icons.mic),
          ),
        ],
      ),
      body: _prefilling
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                projectsAsync.when(
                  data: (projects) {
                    return DropdownButtonFormField<String>(
                      initialValue: _projectId,
                      items: projects
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        final selected = projects.where((p) => p.id == value);
                        setState(() {
                          _projectId = value;
                          _projectName = selected.isEmpty
                              ? ''
                              : selected.first.name;
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Project'),
                    );
                  },
                  error: (e, _) => Text(e.toString()),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  items: const [
                    DropdownMenuItem(value: 'labor', child: Text('Labor')),
                    DropdownMenuItem(
                      value: 'materials',
                      child: Text('Materials'),
                    ),
                    DropdownMenuItem(
                      value: 'equipment',
                      child: Text('Equipment'),
                    ),
                    DropdownMenuItem(
                      value: 'transport',
                      child: Text('Transport'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) =>
                      setState(() => _category = value ?? _category),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_date.toIso8601String().split('T').first),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: _date,
                    );
                    if (date != null) {
                      setState(() => _date = date);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _supplierController,
                  decoration: const InputDecoration(
                    labelText: 'Supplier Name (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.expenseId == null
                              ? 'Save Expense'
                              : 'Update Expense',
                        ),
                ),
              ],
            ),
    );
  }
}
