import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/constants/accounting_categories.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/services/attachment_validation_service.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/presentation/widgets/entity_autocomplete_field.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

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
            onPressed: () =>
                appNavigateBack(context, fallbackRoute: AppRoutes.dashboard),
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
  final _purposeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _supplierController = TextEditingController();
  String _category = AccountingCategories.materials;
  String _currency = 'EGP';
  String _paymentMethod = 'cash';
  String _paymentStatus = PaymentStatuses.unpaid;
  String? _projectId;
  String _projectName = '';
  String? _entityId;
  String _entityName = '';
  DateTime _date = DateTime.now();
  bool _loading = false;
  String? _error;
  final _pickedFiles = <PlatformFile>[];

  @override
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _supplierController.dispose();
    super.dispose();
  }

  Future<void> _save({bool addAnother = false}) async {
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
      final attachments = <Attachment>[];
      if (_pickedFiles.isNotEmpty) {
        for (final file in _pickedFiles) {
          if (file.path == null) {
            continue;
          }
          final uploaded = await ref
              .read(storageUploadServiceProvider)
              .uploadAttachment(
                userId: userId,
                localFilePath: file.path!,
                fileName: file.name,
              );
          attachments.add(
            Attachment(
              id: const Uuid().v4(),
              fileName: uploaded.fileName,
              storagePath: uploaded.storagePath,
              contentType: uploaded.contentType,
              uploadedAt: DateTime.now(),
              downloadUrl: uploaded.downloadUrl,
            ),
          );
        }
      }
      final resolvedEntity = await _resolveEntity(
        workspaceId: workspaceId,
        fallbackName: _supplierController.text.trim(),
        type: 'supplier',
      );
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
            purpose: _purposeController.text.trim(),
            description: _descriptionController.text.trim(),
            notes: _notesController.text.trim(),
            supplierName: _supplierController.text.trim(),
            entityId: resolvedEntity.id,
            entityName: resolvedEntity.name,
            entityType: 'supplier',
            paymentMethod: _paymentMethod,
            paymentStatus: _paymentStatus,
            projectTotalExpensesBefore: selectedProject?.totalExpenses,
            attachments: attachments.isNotEmpty ? attachments : null,
          );
      if (mounted) {
        if (result.queued) {
          await ref.read(offlineQueueCoordinatorProvider).refreshCounts();
          unawaited(ref.read(offlineQueueCoordinatorProvider).drainNow());
          if (!mounted) return;
          pushAppUiNotice(ref, l10n.t('queuedForSync'));
        }
        if (addAnother) {
          setState(() {
            _amountController.clear();
            _purposeController.clear();
            _descriptionController.clear();
            _notesController.clear();
            _pickedFiles.clear();
            _error = null;
            _date = DateTime.now();
          });
          return;
        }
        appNavigateBack(context, fallbackRoute: AppRoutes.dashboard);
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
        setState(
          () => _error = AppLocalizations.of(
            context,
          ).t('unexpectedErrorTryAgain'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<({String? id, String? name})> _resolveEntity({
    required String workspaceId,
    required String fallbackName,
    required String type,
  }) async {
    final name = (_entityName.isNotEmpty ? _entityName : fallbackName).trim();
    if (name.isEmpty) {
      return (id: _entityId, name: null);
    }
    if (_entityId != null && _entityId!.isNotEmpty) {
      return (id: _entityId, name: name);
    }
    final entity = await ref.read(entityRepositoryProvider).ensureEntity(
          workspaceId: workspaceId,
          name: name,
          type: type,
        );
    return (id: entity?.id ?? _entityId, name: entity?.name ?? name);
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: AttachmentValidationService.allowedExtensionsForPicker,
    );
    if (result == null) {
      return;
    }

    final invalidMessages = <String>[];
    final validFiles = <PlatformFile>[];

    for (final file in result.files.where((file) => file.path != null)) {
      final validationError = AttachmentValidationService.validatePickedFile(
        file,
      );
      if (validationError != null) {
        invalidMessages.add(validationError);
        continue;
      }
      validFiles.add(file);
    }

    setState(() {
      _pickedFiles.addAll(validFiles);
      if (invalidMessages.isNotEmpty) {
        _error = invalidMessages.join('\n');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
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
                _projectName = selected.isEmpty ? '' : selected.first.name;
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
              value: AccountingCategories.labor,
              label: l10n.expenseCategoryLabel(AccountingCategories.labor),
            ),
            DropdownMenuEntry(
              value: AccountingCategories.materials,
              label: l10n.expenseCategoryLabel(AccountingCategories.materials),
            ),
            DropdownMenuEntry(
              value: AccountingCategories.equipment,
              label: l10n.expenseCategoryLabel(AccountingCategories.equipment),
            ),
            DropdownMenuEntry(
              value: AccountingCategories.transport,
              label: l10n.expenseCategoryLabel(AccountingCategories.transport),
            ),
            DropdownMenuEntry(
              value: AccountingCategories.storage,
              label: l10n.expenseCategoryLabel(AccountingCategories.storage),
            ),
            DropdownMenuEntry(
              value: AccountingCategories.rentals,
              label: l10n.expenseCategoryLabel(AccountingCategories.rentals),
            ),
            DropdownMenuEntry(
              value: AccountingCategories.payments,
              label: l10n.expenseCategoryLabel(AccountingCategories.payments),
            ),
            DropdownMenuEntry(
              value: AccountingCategories.other,
              label: l10n.expenseCategoryLabel(AccountingCategories.other),
            ),
          ],
          onSelected: (value) => setState(() => _category = value ?? _category),
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
          onSelected: (value) => setState(() => _currency = value ?? _currency),
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
        EntityAutocompleteField(
          workspaceId: workspaceId ?? '',
          label: l10n.t('entityNameOptional'),
          initialEntityId: _entityId,
          initialEntityName: _entityName.isNotEmpty ? _entityName : null,
          onChanged: (entityId, entityName) {
            setState(() {
              _entityId = entityId;
              _entityName = entityName ?? '';
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.t('notes')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _purposeController,
          decoration: InputDecoration(labelText: l10n.t('purpose')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          decoration: InputDecoration(labelText: l10n.t('description')),
        ),
        const SizedBox(height: 12),
        BelowDropdownField<String>(
          label: l10n.t('paymentMethod'),
          value: _paymentMethod,
          entries: [
            DropdownMenuEntry(
              value: 'cash',
              label: l10n.paymentMethodLabel('cash'),
            ),
            DropdownMenuEntry(
              value: 'bank',
              label: l10n.paymentMethodLabel('bank'),
            ),
            DropdownMenuEntry(
              value: 'check',
              label: l10n.paymentMethodLabel('check'),
            ),
          ],
          onSelected: (value) =>
              setState(() => _paymentMethod = value ?? _paymentMethod),
        ),
        const SizedBox(height: 12),
        BelowDropdownField<String>(
          label: l10n.t('paymentStatus'),
          value: _paymentStatus,
          entries: [
            DropdownMenuEntry(
              value: PaymentStatuses.unpaid,
              label: l10n.paymentStatusLabel(PaymentStatuses.unpaid),
            ),
            DropdownMenuEntry(
              value: PaymentStatuses.partial,
              label: l10n.paymentStatusLabel(PaymentStatuses.partial),
            ),
            DropdownMenuEntry(
              value: PaymentStatuses.paid,
              label: l10n.paymentStatusLabel(PaymentStatuses.paid),
            ),
          ],
          onSelected: (value) =>
              setState(() => _paymentStatus = value ?? _paymentStatus),
        ),
        const SizedBox(height: 12),
        Text('Attachments', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_pickedFiles.isNotEmpty)
          Column(
            children: _pickedFiles
                .asMap()
                .entries
                .map(
                  (entry) => Dismissible(
                    key: ValueKey(entry.value.path ?? entry.value.name),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) {
                      setState(() => _pickedFiles.removeAt(entry.key));
                    },
                    background: Container(
                      color: Colors.redAccent,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description),
                      title: Text(entry.value.name),
                      subtitle: Text(entry.value.path ?? ''),
                    ),
                  ),
                )
                .toList(),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        FilledButton.tonal(
          onPressed: _loading ? null : _pickAttachments,
          child: const Text('Select attachments'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : () => _save(addAnother: false),
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
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: _loading ? null : () => _save(addAnother: true),
                child: Text(l10n.t('saveAndAddAnother')),
              ),
            ),
          ],
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
    final invalidProject =
        billedByProject && (totalWage == null || totalWage <= 0);
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
        setState(
          () => _error = AppLocalizations.of(
            context,
          ).t('unexpectedErrorTryAgain'),
        );
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
                  .map((w) => DropdownMenuEntry(value: w.id, label: w.name))
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
            final worker = _selectedWorker(
              workersAsync.valueOrNull ?? const [],
            );
            if (worker == null) return const SizedBox.shrink();
            if (worker.billingType == 'project') {
              return TextField(
                controller: _totalWageController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.t('totalWage')),
              );
            }
            final days = double.tryParse(_daysController.text.trim()) ?? 0;
            final total = days * worker.dailyWage;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _daysController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: l10n.t('daysWorked')),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.t(
                    'dailyWageWithValue',
                    params: {'value': worker.dailyWage.toStringAsFixed(2)},
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
