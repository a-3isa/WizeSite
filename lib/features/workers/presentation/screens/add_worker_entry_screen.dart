import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/attachment_validation_service.dart';
import 'package:buildtrack_app/core/utils/number_parser.dart';
import 'package:buildtrack_app/core/utils/thousands_separator_input_formatter.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

class AddWorkerEntryScreen extends ConsumerStatefulWidget {
  const AddWorkerEntryScreen({
    required this.workerId,
    this.entryId,
    this.projectId,
    super.key,
  });

  final String workerId;
  final String? entryId;
  final String? projectId;

  @override
  ConsumerState<AddWorkerEntryScreen> createState() =>
      _AddWorkerEntryScreenState();
}

class _AddWorkerEntryScreenState extends ConsumerState<AddWorkerEntryScreen> {
  final _daysController = TextEditingController(text: '1');
  final _totalWageController = TextEditingController();
  final _notesController = TextEditingController();
  String? _workerId;
  String? _projectId;
  DateTime _date = DateTime.now();
  final _pickedFiles = <PlatformFile>[];
  final _attachments = <Attachment>[];
  bool _loading = false;
  bool _prefilling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.workerId != 'new') {
      _workerId = widget.workerId;
    }
    if (widget.entryId != null) {
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
      final entry = await ref
          .read(workerEntryRepositoryProvider)
          .getEntry(widget.entryId!);
      if (entry != null && mounted) {
        setState(() {
          _workerId = entry.workerId;
          _projectId = entry.projectId;
          _daysController.text = ThousandsSeparatorInputFormatter.formatInitial(
            entry.daysWorked.toStringAsFixed(2),
          );
          _totalWageController.text =
              ThousandsSeparatorInputFormatter.formatInitial(
                entry.totalCost.toStringAsFixed(2),
              );
          _notesController.text = entry.notes;
          _date = entry.date;
          _attachments
            ..clear()
            ..addAll(entry.attachments);
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
    _daysController.dispose();
    _totalWageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.pickFiles(
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

  String _fallbackRoute() {
    if (_workerId != null && _workerId!.isNotEmpty && _workerId != 'new') {
      return AppRoutes.workerDetailPath(_workerId!);
    }
    return AppRoutes.workers;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    final days = NumberParser.parseDouble(_daysController.text);
    final totalWage = NumberParser.parseDouble(_totalWageController.text);
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    final selectedWorker = _selectedWorker(
      ref.read(workersProvider).value ?? const [],
    );
    if (_workerId == null || _projectId == null || selectedWorker == null) {
      return;
    }
    final billedByProject = selectedWorker.billingType == 'project';
    final invalidDaily =
        !billedByProject &&
        (days == null || days <= 0 || selectedWorker.dailyWage < 0);
    final invalidProject =
        billedByProject && (totalWage == null || totalWage < 0);
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
      final attachments = <Attachment>[];
      for (final file in _pickedFiles) {
        final path = file.path;
        if (path == null) {
          continue;
        }
        final uploaded = await ref
            .read(storageUploadServiceProvider)
            .uploadAttachment(
              userId: userId,
              localFilePath: path,
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
      attachments.addAll(_attachments);
      var queued = false;
      if (widget.entryId == null) {
        final projects = ref.read(projectsProvider).value ?? [];
        final matches = projects.where((project) => project.id == _projectId);
        final selectedProject = matches.isEmpty ? null : matches.first;
        final result = await ref
            .read(workerEntryRepositoryProvider)
            .createEntry(
              workspaceId: workspaceId,
              userId: userId,
              workerId: _workerId!,
              projectId: _projectId!,
              daysWorked: billedByProject ? 1 : days!,
              dailyWage: billedByProject
                  ? totalWage!
                  : selectedWorker.dailyWage,
              date: _date,
              notes: _notesController.text.trim(),
              attachments: attachments,
              projectTotalExpensesBefore: selectedProject?.totalExpenses,
            );
        queued = result.queued;
      } else {
        await ref
            .read(workerEntryRepositoryProvider)
            .updateEntry(
              entryId: widget.entryId!,
              projectId: _projectId!,
              daysWorked: billedByProject ? 1 : days!,
              dailyWage: billedByProject
                  ? totalWage!
                  : selectedWorker.dailyWage,
              date: _date,
              notes: _notesController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    final workersAsync = ref.watch(workersProvider);
    return AppBackScope(
      fallbackRoute: _fallbackRoute(),
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: widget.entryId == null
              ? l10n.t('addWorkerEntryTitle')
              : l10n.t('editWorkerEntryTitle'),
          fallbackRoute: _fallbackRoute(),
        ),
        body: _prefilling
            ? const AppLoadingSkeleton(lineCount: 8)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  workersAsync.whenStale(
                    data: (workers) {
                      final selectedWorkerId = _resolvedWorkerId(workers);
                      final fixedWorkerId = widget.workerId == 'new'
                          ? null
                          : widget.workerId;
                      final showWorkerPicker =
                          fixedWorkerId == null || selectedWorkerId == null;
                      if (!showWorkerPicker) {
                        return const SizedBox.shrink();
                      }
                      return BelowDropdownField<String>(
                        label: l10n.t('workerName'),
                        value: selectedWorkerId,
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
                      );
                    },
                    error: (e, _) => Text(appErrorMessage(l10n, e)),
                    loading: () => const AppLoadingSkeleton(
                      lineCount: 2,
                      padding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  projectsAsync.whenStale(
                    data: (projects) => BelowDropdownField<String>(
                      label: l10n.t('project'),
                      value: _projectId,
                      entries: projects
                          .map(
                            (p) =>
                                DropdownMenuEntry(value: p.id, label: p.name),
                          )
                          .toList(),
                      onSelected: (value) => setState(() => _projectId = value),
                    ),
                    error: (e, _) => Text(appErrorMessage(l10n, e)),
                    loading: () => const AppLoadingSkeleton(
                      lineCount: 2,
                      padding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final worker = _selectedWorker(
                        workersAsync.value ?? const [],
                      );
                      if (worker == null) {
                        return const SizedBox.shrink();
                      }
                      if (worker.billingType == 'project') {
                        return TextField(
                          controller: _totalWageController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: const [
                            ThousandsSeparatorInputFormatter(),
                          ],
                          decoration: InputDecoration(
                            labelText: l10n.t('totalWage'),
                          ),
                        );
                      }
                      final days =
                          NumberParser.parseDouble(_daysController.text) ?? 0;
                      final total = days * worker.dailyWage;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _daysController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: const [
                              ThousandsSeparatorInputFormatter(),
                            ],
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: l10n.t('daysWorked'),
                            ),
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
                        params: {
                          'value': _date.toIso8601String().split('T').first,
                        },
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
                      if (picked != null) {
                        setState(() => _date = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: l10n.t('notes')),
                  ),
                  const SizedBox(height: 12),
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
                            widget.entryId == null
                                ? l10n.t('saveWorkerEntry')
                                : l10n.t('updateWorkerEntry'),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  String? _resolvedWorkerId(List<WorkerProfile> workers) {
    final currentWorkerId = _workerId;
    if (currentWorkerId == null ||
        currentWorkerId.isEmpty ||
        currentWorkerId == 'new') {
      return null;
    }
    final exists = workers.any((worker) => worker.id == currentWorkerId);
    if (exists) {
      return currentWorkerId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _workerId == currentWorkerId) {
        setState(() => _workerId = null);
      }
    });
    return null;
  }

  WorkerProfile? _selectedWorker(List<WorkerProfile> workers) {
    final id = _workerId;
    if (id == null || id.isEmpty || id == 'new') {
      return null;
    }
    for (final worker in workers) {
      if (worker.id == id) {
        return worker;
      }
    }
    return null;
  }
}
