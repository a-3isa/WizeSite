import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/firebase_functions_error_message.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddWorkerEntryScreen extends ConsumerStatefulWidget {
  const AddWorkerEntryScreen({required this.workerId, this.entryId, super.key});

  final String workerId;
  final String? entryId;

  @override
  ConsumerState<AddWorkerEntryScreen> createState() =>
      _AddWorkerEntryScreenState();
}

class _AddWorkerEntryScreenState extends ConsumerState<AddWorkerEntryScreen> {
  final _daysController = TextEditingController(text: '1');
  final _wageController = TextEditingController();
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
      _prefill();
    }
  }

  Future<void> _prefill() async {
    setState(() => _prefilling = true);
    final entry = await ref
        .read(workerEntryRepositoryProvider)
        .getEntry(widget.entryId!);
    if (entry != null && mounted) {
      setState(() {
        _workerId = entry.workerId;
        _projectId = entry.projectId;
        _daysController.text = entry.daysWorked.toStringAsFixed(2);
        _wageController.text = entry.dailyWage.toStringAsFixed(2);
        _notesController.text = entry.notes;
        _date = entry.date;
      });
    }
    if (mounted) {
      setState(() => _prefilling = false);
    }
  }

  @override
  void dispose() {
    _daysController.dispose();
    _wageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    final days = double.tryParse(_daysController.text.trim());
    final wage = double.tryParse(_wageController.text.trim());
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    if (_workerId == null ||
        _projectId == null ||
        days == null ||
        wage == null ||
        days <= 0) {
      setState(() => _error = l10n.t('fillWorkerProjectDaysWage'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.entryId == null) {
        await ref
            .read(workerEntryRepositoryProvider)
            .createEntry(
              workspaceId: workspaceId,
              userId: userId,
              workerId: _workerId!,
              projectId: _projectId!,
              daysWorked: days,
              dailyWage: wage,
              date: _date,
              notes: _notesController.text.trim(),
            );
      } else {
        await ref
            .read(workerEntryRepositoryProvider)
            .updateEntry(
              entryId: widget.entryId!,
              projectId: _projectId!,
              daysWorked: days,
              dailyWage: wage,
              date: _date,
              notes: _notesController.text.trim(),
            );
      }
      if (mounted) {
        context.pop();
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        if (mounted) {
          context.push(
            '${AppRoutes.subscriptionLimit}?limit=workerEntriesPerMonth',
          );
        }
      } else if (mounted) {
        setState(() => _error = firebaseFunctionsErrorMessage(e, l10n));
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.entryId == null
              ? l10n.t('addWorkerEntryTitle')
              : l10n.t('editWorkerEntryTitle'),
        ),
      ),
      body: _prefilling
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_workerId == null)
                  workersAsync.when(
                    data: (workers) => DropdownButtonFormField<String>(
                      initialValue: _workerId,
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
                    ),
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
                TextField(
                  controller: _daysController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.t('daysWorked')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _wageController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.t('dailyWage')),
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
    );
  }
}
