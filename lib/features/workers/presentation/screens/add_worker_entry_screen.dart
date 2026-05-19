import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
          _daysController.text = entry.daysWorked.toStringAsFixed(2);
          _totalWageController.text = entry.totalCost.toStringAsFixed(2);
          _notesController.text = entry.notes;
          _date = entry.date;
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
    final days = double.tryParse(_daysController.text.trim());
    final totalWage = double.tryParse(_totalWageController.text.trim());
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    final selectedWorker = _selectedWorker(
      ref.read(workersProvider).valueOrNull ?? const [],
    );
    if (_workerId == null || _projectId == null || selectedWorker == null) {
      return;
    }
    final billedByProject = selectedWorker.billingType == 'project';
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
      var queued = false;
      if (widget.entryId == null) {
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
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  workersAsync.when(
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
                      return DropdownButtonFormField<String>(
                        initialValue: selectedWorkerId,
                        items: workers
                            .map(
                              (worker) => DropdownMenuItem(
                                value: worker.id,
                                child: Text(worker.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _workerId = value),
                        decoration: InputDecoration(
                          labelText: l10n.t('workerName'),
                        ),
                      );
                    },
                    error: (e, _) => Text(e.toString()),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                  ),
                  const SizedBox(height: 12),
                  projectsAsync.when(
                    data: (projects) => DropdownButtonFormField<String>(
                      initialValue: _projectId,
                      items: projects
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _projectId = value),
                      decoration: InputDecoration(labelText: l10n.t('project')),
                    ),
                    error: (e, _) => Text(e.toString()),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final worker = _selectedWorker(
                        workersAsync.valueOrNull ?? const [],
                      );
                      if (worker == null) {
                        return const SizedBox.shrink();
                      }
                      if (worker.billingType == 'project') {
                        return TextField(
                          controller: _totalWageController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.t('totalWage'),
                          ),
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
