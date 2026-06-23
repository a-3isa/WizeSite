import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/accounting_entity_types.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/accounting_categories.dart';
import 'package:buildtrack_app/core/utils/number_parser.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/services/attachment_validation_service.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/presentation/widgets/entity_autocomplete_field.dart';
import 'package:buildtrack_app/features/expenses/data/expense_entry_defaults.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
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
  final _purposeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _supplierController = TextEditingController();
  final _daysController = TextEditingController(text: '1');
  final _quantityController = TextEditingController(text: '1');
  String? _category;
  String _paymentMethod = 'cash';
  String _paymentStatus = PaymentStatuses.unpaid;
  String? _projectId;
  String? _workerId;
  String _projectName = '';
  String? _entityId;
  String _entityName = '';
  DateTime _date = DateTime.now();
  bool _loading = false;
  bool _prefilling = false;
  bool _manualEntityInput = false;
  double? _selectedEntityDefaultRate;
  String? _error;
  final _pickedFiles = <PlatformFile>[];
  final _attachments = <Attachment>[];

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
    } else {
      final defaults = ref.read(expenseEntryDefaultsProvider);
      _paymentMethod = defaults.paymentMethod;
      _paymentStatus = defaults.paymentStatus;
      if (widget.projectId != null) {
        _projectId = widget.projectId;
      }
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
          _purposeController.text = expense.purpose;
          _descriptionController.text = expense.description;
          _notesController.text = expense.notes;
          _supplierController.text = expense.supplierName;
          _entityId = expense.entityId;
          _entityName = expense.entityName;
          _paymentMethod = expense.paymentMethod.isEmpty
              ? 'cash'
              : expense.paymentMethod;
          _paymentStatus = expense.paymentStatus;
          _date = expense.date;
          _attachments.clear();
          _attachments.addAll(expense.attachments);
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
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _supplierController.dispose();
    _daysController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  String _fallbackRoute() {
    final projectId = _projectId ?? widget.projectId;
    if (projectId != null && projectId.isNotEmpty) {
      return AppRoutes.projectExpensesPath(projectId);
    }
    return AppRoutes.projects;
  }

  Future<List<Attachment>> _uploadAttachments(String userId) async {
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
            size: uploaded.size,
          ),
        );
      }
    }
    attachments.addAll(_attachments);
    return attachments;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    final category = _category;
    final amount = NumberParser.parseDouble(_amountController.text);
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    if (category == null) {
      setState(() => _error = l10n.t('fillRequiredFields'));
      return;
    }
    if (category == AccountingCategories.worker && widget.expenseId == null) {
      await _saveWorkerEntry(
        l10n: l10n,
        workspaceId: workspaceId,
        userId: userId,
      );
      return;
    }
    if (_projectId == null || amount == null || amount < 0) {
      setState(() => _error = l10n.t('selectProjectAndValidAmount'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var queued = false;
      final attachments = await _uploadAttachments(userId);
      final entityType = _entityTypeForCategory(category);
      final resolvedEntity = await _resolveEntity(
        workspaceId: workspaceId,
        fallbackName: _supplierController.text.trim(),
        type: entityType,
      );
      final currency =
          ref.read(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
          'EGP';

      if (widget.expenseId == null) {
        String finalProjectName = _projectName;
        final projects = ref.read(projectsProvider).valueOrNull ?? [];
        final matches = projects.where((project) => project.id == _projectId);
        final selectedProject = matches.isEmpty ? null : matches.first;
        if (finalProjectName.isEmpty && _projectId != null) {
          if (selectedProject != null) {
            finalProjectName = selectedProject.name;
          }
        }
        final result = await ref
            .read(expenseRepositoryProvider)
            .createExpense(
              workspaceId: workspaceId,
              userId: userId,
              projectId: _projectId!,
              projectName: finalProjectName,
              category: category,
              amount: amount,
              currency: currency,
              date: _date,
              purpose: _purposeController.text.trim(),
              description: _descriptionController.text.trim(),
              notes: _notesController.text.trim(),
              supplierName: _supplierController.text.trim(),
              entityId: resolvedEntity.id,
              entityName: resolvedEntity.name,
              entityType: entityType,
              paymentMethod: _paymentMethod,
              paymentStatus: _paymentStatus,
              projectTotalExpensesBefore: selectedProject?.totalExpenses,
              attachments: attachments.isNotEmpty ? attachments : null,
            );
        queued = result.queued;
        ref
            .read(expenseEntryDefaultsProvider.notifier)
            .state = ExpenseEntryDefaults(
          category: category,
          paymentMethod: _paymentMethod,
          paymentStatus: _paymentStatus,
        );
      } else {
        await ref
            .read(expenseRepositoryProvider)
            .updateExpense(
              expenseId: widget.expenseId!,
              category: category,
              amount: amount,
              date: _date,
              purpose: _purposeController.text.trim(),
              description: _descriptionController.text.trim(),
              notes: _notesController.text.trim(),
              supplierName: _supplierController.text.trim(),
              entityId: resolvedEntity.id,
              entityName: resolvedEntity.name,
              entityType: entityType,
              paymentMethod: _paymentMethod,
              paymentStatus: _paymentStatus,
              attachments: attachments,
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
    final entity = await ref
        .read(entityRepositoryProvider)
        .ensureEntity(workspaceId: workspaceId, name: name, type: type);
    return (id: entity?.id ?? _entityId, name: entity?.name ?? name);
  }

  String _entityTypeForCategory(String category) {
    return switch (category) {
      AccountingCategories.worker => AccountingEntityTypes.worker,
      AccountingCategories.contractor => AccountingEntityTypes.contractor,
      AccountingCategories.equipment => AccountingEntityTypes.equipmentProvider,
      AccountingCategories.transport => AccountingEntityTypes.transportProvider,
      _ => AccountingEntityTypes.supplier,
    };
  }

  bool get _resourceCategorySelected {
    final category = _category;
    return category == AccountingCategories.contractor ||
        category == AccountingCategories.equipment ||
        category == AccountingCategories.transport;
  }

  Future<void> _applyEntityDefaults(String entityId) async {
    final entity = await ref
        .read(entityRepositoryProvider)
        .getEntityById(entityId);
    if (!mounted || entity == null) {
      return;
    }
    final rate = entity.defaultRate;
    setState(() {
      _selectedEntityDefaultRate = rate;
    });
    _recalculateResourceAmount(force: true);
  }

  void _recalculateResourceAmount({bool force = false}) {
    final rate = _selectedEntityDefaultRate;
    if (rate == null) {
      return;
    }
    final quantity = NumberParser.parseDouble(_quantityController.text) ?? 1;
    final nextAmount = (rate * quantity).toStringAsFixed(2);
    if (force || _amountController.text.trim().isEmpty) {
      setState(() => _amountController.text = nextAmount);
    }
  }

  Future<void> _saveWorkerEntry({
    required AppLocalizations l10n,
    required String workspaceId,
    required String userId,
  }) async {
    final days = NumberParser.parseDouble(_daysController.text);
    final worker = _selectedWorker(ref.read(workersProvider).valueOrNull ?? []);
    if (_projectId == null || worker == null || days == null || days <= 0) {
      setState(() => _error = l10n.t('fillWorkerProjectDaysWage'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final attachments = await _uploadAttachments(userId);
      final projects = ref.read(projectsProvider).valueOrNull ?? [];
      final matches = projects.where((project) => project.id == _projectId);
      final selectedProject = matches.isEmpty ? null : matches.first;
      final result = await ref
          .read(workerEntryRepositoryProvider)
          .createEntry(
            workspaceId: workspaceId,
            userId: userId,
            workerId: worker.id,
            projectId: _projectId!,
            daysWorked: days,
            dailyWage: worker.dailyWage,
            date: _date,
            notes: _notesController.text.trim(),
            attachments: attachments,
            projectTotalExpensesBefore: selectedProject?.totalExpenses,
          );
      if (mounted) {
        if (result.queued) {
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
          context.push(
            '${AppRoutes.subscriptionLimit}?limit=workerEntriesPerMonth',
          );
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

  WorkerProfile? _selectedWorker(List<WorkerProfile> workers) {
    final id = _workerId;
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final worker in workers) {
      if (worker.id == id) {
        return worker;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final workersAsync = ref.watch(workersProvider);
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
            ? const AppLoadingSkeleton(lineCount: 8)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                  ],
                  projectsAsync.whenStale(
                    data: (projects) {
                      return BelowDropdownField<String>(
                        label: l10n.t('project'),
                        value: _projectId,
                        entries: projects
                            .map(
                              (p) =>
                                  DropdownMenuEntry(value: p.id, label: p.name),
                            )
                            .toList(),
                        onSelected: (value) {
                          final selected = projects.where((p) => p.id == value);
                          setState(() {
                            _projectId = value;
                            _projectName = selected.isEmpty
                                ? ''
                                : selected.first.name;
                          });
                        },
                      );
                    },
                    error: (e, _) => Text(appErrorMessage(l10n, e)),
                    loading: () => const AppLoadingSkeleton(
                      lineCount: 2,
                      padding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  BelowDropdownField<String>(
                    label: l10n.t('category'),
                    value: _category,
                    entries: [
                      DropdownMenuEntry(
                        value: AccountingCategories.worker,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.worker,
                        ),
                      ),
                      DropdownMenuEntry(
                        value: AccountingCategories.contractor,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.contractor,
                        ),
                      ),
                      DropdownMenuEntry(
                        value: AccountingCategories.labor,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.labor,
                        ),
                      ),
                      DropdownMenuEntry(
                        value: AccountingCategories.materials,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.materials,
                        ),
                      ),
                      DropdownMenuEntry(
                        value: AccountingCategories.equipment,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.equipment,
                        ),
                      ),
                      DropdownMenuEntry(
                        value: AccountingCategories.transport,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.transport,
                        ),
                      ),
                      DropdownMenuEntry(
                        value: AccountingCategories.storage,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.storage,
                        ),
                      ),
                      DropdownMenuEntry(
                        value: AccountingCategories.rentals,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.rentals,
                        ),
                      ),
                      DropdownMenuEntry(
                        value: AccountingCategories.payments,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.payments,
                        ),
                      ),
                      DropdownMenuEntry(
                        value: AccountingCategories.other,
                        label: l10n.expenseCategoryLabel(
                          AccountingCategories.other,
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _category = value;
                        _entityId = null;
                        _entityName = '';
                        _manualEntityInput = false;
                        _selectedEntityDefaultRate = null;
                        _quantityController.text = '1';
                      });
                    },
                  ),
                  if (_category == null) const SizedBox(height: 12),
                  if (_category == AccountingCategories.worker) ...[
                    const SizedBox(height: 12),
                    workersAsync.whenStale(
                      data: (workers) => BelowDropdownField<String>(
                        label: l10n.t('workerName'),
                        value: _workerId,
                        entries: workers
                            .map(
                              (worker) => DropdownMenuEntry(
                                value: worker.id,
                                label: worker.name,
                              ),
                            )
                            .toList(),
                        onSelected: (value) =>
                            setState(() => _workerId = value),
                      ),
                      error: (e, _) => Text(appErrorMessage(l10n, e)),
                      loading: () => const AppLoadingSkeleton(
                        lineCount: 2,
                        padding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _daysController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l10n.t('daysWorked'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final worker = _selectedWorker(
                          workersAsync.valueOrNull ?? const [],
                        );
                        if (worker == null) {
                          return const SizedBox.shrink();
                        }
                        final days =
                            NumberParser.parseDouble(_daysController.text) ?? 0;
                        return Text(
                          l10n.t(
                            'calculatedTotalWageWithValue',
                            params: {
                              'value': (days * worker.dailyWage)
                                  .toStringAsFixed(2),
                            },
                          ),
                        );
                      },
                    ),
                  ],
                  if (_category != null &&
                      _category != AccountingCategories.worker) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: l10n.t('amount')),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _resourceCategorySelected
                                ? l10n.t('entityNameOptional')
                                : l10n.t('supplierNameOptional'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _manualEntityInput = !_manualEntityInput,
                          ),
                          icon: Icon(
                            _manualEntityInput
                                ? Icons.list_alt_outlined
                                : Icons.edit_outlined,
                          ),
                          label: Text(
                            _manualEntityInput
                                ? l10n.t('chooseSavedResource')
                                : l10n.t('manualInput'),
                          ),
                        ),
                      ],
                    ),
                    if (_manualEntityInput)
                      TextField(
                        controller: _supplierController,
                        decoration: InputDecoration(
                          labelText: l10n.t('entityNameOptional'),
                        ),
                      )
                    else
                      EntityAutocompleteField(
                        workspaceId: workspaceId ?? '',
                        label: l10n.t('entityNameOptional'),
                        entityType: _entityTypeForCategory(_category!),
                        showAllOnEmpty: _resourceCategorySelected,
                        initialEntityId: _entityId,
                        initialEntityName: _entityName.isNotEmpty
                            ? _entityName
                            : null,
                        onChanged: (entityId, entityName) {
                          setState(() {
                            _entityId = entityId;
                            _entityName = entityName ?? '';
                            _supplierController.text = entityName ?? '';
                          });
                          if (entityId != null && entityId.isNotEmpty) {
                            unawaited(_applyEntityDefaults(entityId));
                          }
                        },
                      ),
                    if (_resourceCategorySelected) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) =>
                            _recalculateResourceAmount(force: true),
                        decoration: InputDecoration(
                          labelText: l10n.t('quantity'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _purposeController,
                      decoration: InputDecoration(labelText: l10n.t('purpose')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: l10n.t('description'),
                      ),
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
                      onSelected: (value) => setState(
                        () => _paymentMethod = value ?? _paymentMethod,
                      ),
                    ),
                    const SizedBox(height: 12),
                    BelowDropdownField<String>(
                      label: l10n.t('paymentStatus'),
                      value: _paymentStatus,
                      entries: [
                        DropdownMenuEntry(
                          value: PaymentStatuses.unpaid,
                          label: l10n.paymentStatusLabel(
                            PaymentStatuses.unpaid,
                          ),
                        ),
                        DropdownMenuEntry(
                          value: PaymentStatuses.partial,
                          label: l10n.paymentStatusLabel(
                            PaymentStatuses.partial,
                          ),
                        ),
                        DropdownMenuEntry(
                          value: PaymentStatuses.paid,
                          label: l10n.paymentStatusLabel(PaymentStatuses.paid),
                        ),
                      ],
                      onSelected: (value) => setState(
                        () => _paymentStatus = value ?? _paymentStatus,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: l10n.t('notes')),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_category != null) ...[
                    Text(
                      l10n.t('attachments'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_attachments.isNotEmpty)
                      Column(
                        children: _attachments
                            .asMap()
                            .entries
                            .map(
                              (entry) => Dismissible(
                                key: ValueKey(entry.value.id),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) {
                                  setState(
                                    () => _attachments.removeAt(entry.key),
                                  );
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
                                  leading: const Icon(Icons.attach_file),
                                  title: Text(entry.value.fileName),
                                  subtitle: Text(entry.value.storagePath),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    if (_pickedFiles.isNotEmpty)
                      Column(
                        children: _pickedFiles
                            .asMap()
                            .entries
                            .map(
                              (entry) => Dismissible(
                                key: ValueKey(
                                  entry.value.path ?? entry.value.name,
                                ),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) {
                                  setState(
                                    () => _pickedFiles.removeAt(entry.key),
                                  );
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
                    FilledButton.tonal(
                      onPressed: _loading ? null : _pickAttachments,
                      child: Text(l10n.t('selectAttachments')),
                    ),
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
                ],
              ),
      ),
    );
  }
}
