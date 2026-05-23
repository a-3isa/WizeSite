import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddEntryScreen extends ConsumerStatefulWidget {
  const AddEntryScreen({this.initialTab = 0, super.key});

  final int initialTab;

  @override
  ConsumerState<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends ConsumerState<AddEntryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBackScope(
      fallbackRoute: AppRoutes.dashboard,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const BackButtonIcon(),
            onPressed: () => appNavigateBack(
              context,
              fallbackRoute: AppRoutes.dashboard,
            ),
          ),
          title: Text(
            l10n.t('addEntry'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                icon: const Icon(Icons.receipt_long_outlined, size: 20),
                text: l10n.t('addExpense'),
              ),
              Tab(
                icon: const Icon(Icons.engineering_outlined, size: 20),
                text: l10n.t('addWorkerEntry'),
              ),
            ],
            labelColor: AppColors.constructionOrange,
            unselectedLabelColor: AppColors.textBody,
            indicatorColor: AppColors.constructionOrange,
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _ExpenseFormBody(key: const PageStorageKey('expense-tab')),
            _WorkerEntryFormBody(key: const PageStorageKey('worker-tab')),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expense form body
// ─────────────────────────────────────────────────────────────────────────────

class _ExpenseFormBody extends ConsumerStatefulWidget {
  const _ExpenseFormBody({super.key});

  @override
  ConsumerState<_ExpenseFormBody> createState() => _ExpenseFormBodyState();
}

class _ExpenseFormBodyState extends ConsumerState<_ExpenseFormBody> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _supplierController = TextEditingController();
  String _category = 'materials';
  String _currency = 'EGP';
  String? _projectId;
  String _projectName = '';
  DateTime _date = DateTime.now();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _supplierController.dispose();
    super.dispose();
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
      String finalProjectName = _projectName;
      final projects = ref.read(projectsProvider).valueOrNull ?? [];
      final matches = projects.where((p) => p.id == _projectId);
      final selectedProject = matches.isEmpty ? null : matches.first;
      if (finalProjectName.isEmpty && selectedProject != null) {
        finalProjectName = selectedProject.name;
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
            projectTotalExpensesBefore: selectedProject?.totalExpenses,
          );
      if (mounted) {
        if (result.queued) {
          await ref.read(offlineQueueCoordinatorProvider).refreshCounts();
          unawaited(ref.read(offlineQueueCoordinatorProvider).drainNow());
          if (!mounted) return;
          pushAppUiNotice(ref, l10n.t('queuedForSync'));
        }
        appNavigateBack(context, fallbackRoute: AppRoutes.dashboard);
      }
    } on CallableClientException catch (e) {
      if (e.code == 'failed-precondition') {
        if (mounted) {
          context.push(
            '${AppRoutes.subscriptionLimit}?limit=expensesPerMonth',
          );
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).t('unexpectedErrorTryAgain'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    final defaultCurrency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
    if (_currency == 'EGP' && defaultCurrency != 'EGP') {
      _currency = defaultCurrency;
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        projectsAsync.when(
          data: (projects) => BelowDropdownField<String>(
            label: l10n.t('project'),
            value: _projectId,
            entries: projects
                .map((p) => DropdownMenuEntry(value: p.id, label: p.name))
                .toList(),
            onSelected: (value) {
              final selected = projects.where((p) => p.id == value);
              setState(() {
                _projectId = value;
                _projectName =
                    selected.isEmpty ? '' : selected.first.name;
              });
            },
          ),
          error: (e, _) => Text(e.toString()),
          loading: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        BelowDropdownField<String>(
          label: l10n.t('category'),
          value: _category,
          entries: [
            DropdownMenuEntry(
              value: 'labor',
              label: l10n.expenseCategoryLabel('labor'),
            ),
            DropdownMenuEntry(
              value: 'materials',
              label: l10n.expenseCategoryLabel('materials'),
            ),
            DropdownMenuEntry(
              value: 'equipment',
              label: l10n.expenseCategoryLabel('equipment'),
            ),
            DropdownMenuEntry(
              value: 'transport',
              label: l10n.expenseCategoryLabel('transport'),
            ),
            DropdownMenuEntry(
              value: 'other',
              label: l10n.expenseCategoryLabel('other'),
            ),
          ],
          onSelected: (value) =>
              setState(() => _category = value ?? _category),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.t('amount')),
        ),
        const SizedBox(height: 12),
        BelowDropdownField<String>(
          label: l10n.t('currencyLabel'),
          value: _currency,
          entries: const [
            DropdownMenuEntry(value: 'EGP', label: 'EGP'),
            DropdownMenuEntry(value: 'USD', label: 'USD'),
            DropdownMenuEntry(value: 'SAR', label: 'SAR'),
            DropdownMenuEntry(value: 'AED', label: 'AED'),
          ],
          onSelected: (value) =>
              setState(() => _currency = value ?? _currency),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.t(
              'dateWithValue',
              params: {'value': _date.toIso8601String().split('T').first},
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
            if (date != null) setState(() => _date = date);
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
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.constructionOrange,
          ),
          child: _loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.t('saveExpense')),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Worker entry form body
// ─────────────────────────────────────────────────────────────────────────────

class _WorkerEntryFormBody extends ConsumerStatefulWidget {
  const _WorkerEntryFormBody({super.key});

  @override
  ConsumerState<_WorkerEntryFormBody> createState() =>
      _WorkerEntryFormBodyState();
}

class _WorkerEntryFormBodyState extends ConsumerState<_WorkerEntryFormBody> {
  final _daysController = TextEditingController(text: '1');
  final _totalWageController = TextEditingController();
  final _notesController = TextEditingController();
  String? _workerId;
  String? _projectId;
  DateTime _date = DateTime.now();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _daysController.dispose();
    _totalWageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _resolvedWorkerId(List<WorkerProfile> workers) {
    final id = _workerId;
    if (id == null || id.isEmpty) return null;
    final exists = workers.any((w) => w.id == id);
    if (exists) return id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _workerId == id) setState(() => _workerId = null);
    });
    return null;
  }

  WorkerProfile? _selectedWorker(List<WorkerProfile> workers) {
    final id = _workerId;
    if (id == null || id.isEmpty) return null;
    for (final w in workers) {
      if (w.id == id) return w;
    }
    return null;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    final selectedWorker = _selectedWorker(
      ref.read(workersProvider).valueOrNull ?? const [],
    );
    if (_workerId == null || _projectId == null || selectedWorker == null) {
      setState(() => _error = l10n.t('fillWorkerProjectDaysWage'));
      return;
    }
    final billedByProject = selectedWorker.billingType == 'project';
    final days = double.tryParse(_daysController.text.trim());
    final totalWage = double.tryParse(_totalWageController.text.trim());
    final invalidDaily =
        !billedByProject &&
        (days == null || days <= 0 || selectedWorker.dailyWage <= 0);
    final invalidProject = billedByProject && (totalWage == null || totalWage <= 0);
    if (invalidDaily || invalidProject) {
      setState(
        () => _error = billedByProject
            ? l10n.t('fillWorkerProjectTotalWage')
            : l10n.t('fillWorkerProjectDaysWage'),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = ref.read(projectsProvider).valueOrNull ?? [];
      final matches = projects.where((p) => p.id == _projectId);
      final selectedProject = matches.isEmpty ? null : matches.first;
      final result = await ref
          .read(workerEntryRepositoryProvider)
          .createEntry(
            workspaceId: workspaceId,
            userId: userId,
            workerId: _workerId!,
            projectId: _projectId!,
            daysWorked: billedByProject ? 1 : days!,
            dailyWage: billedByProject ? totalWage! : selectedWorker.dailyWage,
            date: _date,
            notes: _notesController.text.trim(),
            projectTotalExpensesBefore: selectedProject?.totalExpenses,
          );
      if (mounted) {
        if (result.queued) {
          await ref.read(offlineQueueCoordinatorProvider).refreshCounts();
          unawaited(ref.read(offlineQueueCoordinatorProvider).drainNow());
          if (!mounted) return;
          pushAppUiNotice(ref, l10n.t('queuedForSync'));
        }
        appNavigateBack(context, fallbackRoute: AppRoutes.dashboard);
      }
    } on CallableClientException catch (e) {
      if (e.code == 'failed-precondition') {
        if (mounted) {
          context.push(
            '${AppRoutes.subscriptionLimit}?limit=workerEntriesPerMonth',
          );
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).t('unexpectedErrorTryAgain'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workersAsync = ref.watch(workersProvider);
    final projectsAsync = ref.watch(projectsProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        workersAsync.when(
          data: (workers) {
            final resolvedId = _resolvedWorkerId(workers);
            return BelowDropdownField<String>(
              label: l10n.t('workerName'),
              value: resolvedId,
              entries: workers
                  .map(
                    (w) => DropdownMenuEntry(value: w.id, label: w.name),
                  )
                  .toList(),
              onSelected: (value) => setState(() => _workerId = value),
            );
          },
          error: (e, _) => Text(e.toString()),
          loading: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        projectsAsync.when(
          data: (projects) => BelowDropdownField<String>(
            label: l10n.t('project'),
            value: _projectId,
            entries: projects
                .map((p) => DropdownMenuEntry(value: p.id, label: p.name))
                .toList(),
            onSelected: (value) => setState(() => _projectId = value),
          ),
          error: (e, _) => Text(e.toString()),
          loading: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final worker =
                _selectedWorker(workersAsync.valueOrNull ?? const []);
            if (worker == null) return const SizedBox.shrink();
            if (worker.billingType == 'project') {
              return TextField(
                controller: _totalWageController,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: l10n.t('totalWage')),
              );
            }
            final days =
                double.tryParse(_daysController.text.trim()) ?? 0;
            final total = days * worker.dailyWage;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _daysController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      InputDecoration(labelText: l10n.t('daysWorked')),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.t(
                    'dailyWageWithValue',
                    params: {
                      'value': worker.dailyWage.toStringAsFixed(2),
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.t(
                    'calculatedTotalWageWithValue',
                    params: {'value': total.toStringAsFixed(2)},
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.t(
              'dateWithValue',
              params: {'value': _date.toIso8601String().split('T').first},
            ),
          ),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              initialDate: _date,
            );
            if (picked != null) setState(() => _date = picked);
          },
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
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.constructionOrange,
          ),
          child: _loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.t('saveWorkerEntry')),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
