import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({this.expenseId, this.projectId, super.key});

  final String? expenseId;
  final String? projectId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _supplierController = TextEditingController();
  String _category = 'materials';
  String _currency = 'EGP';
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_prefill());
      });
    } else if (widget.projectId != null) {
      _projectId = widget.projectId;
    }
  }

  Future<void> _prefill() async {
    setState(() => _prefilling = true);
    try {
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
          _currency = expense.currency;
          _date = expense.date;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).t('unexpectedErrorTryAgain');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _prefilling = false);
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _supplierController.dispose();
    super.dispose();
  }

  String _fallbackRoute() {
    final projectId = _projectId ?? widget.projectId;
    if (projectId != null && projectId.isNotEmpty) {
      return AppRoutes.projectExpensesPath(projectId);
    }
    return AppRoutes.projects;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    final amount = double.tryParse(_amountController.text.trim());
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    if (_projectId == null || amount == null || amount <= 0) {
      setState(() => _error = l10n.t('selectProjectAndValidAmount'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var queued = false;
      if (widget.expenseId == null) {
        String finalProjectName = _projectName;
        if (finalProjectName.isEmpty && _projectId != null) {
          final projects = ref.read(projectsProvider).valueOrNull ?? [];
          final match = projects.where((p) => p.id == _projectId);
          if (match.isNotEmpty) {
            finalProjectName = match.first.name;
          }
        }
        final result = await ref
            .read(expenseRepositoryProvider)
            .createExpense(
              workspaceId: workspaceId,
              userId: userId,
              projectId: _projectId!,
              projectName: finalProjectName,
              category: _category,
              amount: amount,
              currency: _currency,
              date: _date,
              notes: _notesController.text.trim(),
              supplierName: _supplierController.text.trim(),
            );
        queued = result.queued;
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
        if (queued) {
          await ref.read(offlineQueueCoordinatorProvider).refreshCounts();
          unawaited(ref.read(offlineQueueCoordinatorProvider).drainNow());
          if (!mounted) {
            return;
          }
          pushAppUiNotice(ref, l10n.t('queuedForSync'));
        }
        appNavigateBack(context, fallbackRoute: _fallbackRoute());
      }
    } on CallableClientException catch (e) {
      if (e.code == 'failed-precondition') {
        if (mounted) {
          context.push('${AppRoutes.subscriptionLimit}?limit=expensesPerMonth');
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.t('unexpectedErrorTryAgain'));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    final defaultCurrency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
    if (widget.expenseId == null &&
        _currency == 'EGP' &&
        defaultCurrency != 'EGP') {
      _currency = defaultCurrency;
    }
    return AppBackScope(
      fallbackRoute: _fallbackRoute(),
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: widget.expenseId == null
              ? l10n.t('addExpenseTitle')
              : l10n.t('editExpenseTitle'),
          fallbackRoute: _fallbackRoute(),
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
                        decoration: InputDecoration(
                          labelText: l10n.t('project'),
                        ),
                      );
                    },
                    error: (e, _) => Text(e.toString()),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    items: [
                      DropdownMenuItem(
                        value: 'labor',
                        child: Text(l10n.expenseCategoryLabel('labor')),
                      ),
                      DropdownMenuItem(
                        value: 'materials',
                        child: Text(l10n.expenseCategoryLabel('materials')),
                      ),
                      DropdownMenuItem(
                        value: 'equipment',
                        child: Text(l10n.expenseCategoryLabel('equipment')),
                      ),
                      DropdownMenuItem(
                        value: 'transport',
                        child: Text(l10n.expenseCategoryLabel('transport')),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text(l10n.expenseCategoryLabel('other')),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _category = value ?? _category),
                    decoration: InputDecoration(labelText: l10n.t('category')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.t('amount')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    items: const [
                      DropdownMenuItem(value: 'EGP', child: Text('EGP')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                      DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                      DropdownMenuItem(value: 'AED', child: Text('AED')),
                    ],
                    onChanged: (value) =>
                        setState(() => _currency = value ?? _currency),
                    decoration: InputDecoration(
                      labelText: l10n.t('currencyLabel'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l10n.t(
                        'dateWithValue',
                        params: {
                          'value': _date.toIso8601String().split('T').first,
                        },
                      ),
                    ),
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
                    decoration: InputDecoration(
                      labelText: l10n.t('supplierNameOptional'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: l10n.t('notes')),
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
                                ? l10n.t('saveExpense')
                                : l10n.t('updateExpense'),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
