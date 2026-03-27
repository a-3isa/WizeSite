import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AddWorkerScreen extends ConsumerStatefulWidget {
  const AddWorkerScreen({this.workerId, super.key});

  final String? workerId;

  @override
  ConsumerState<AddWorkerScreen> createState() => _AddWorkerScreenState();
}

class _AddWorkerScreenState extends ConsumerState<AddWorkerScreen> {
  static const _workerTypes = <String>[
    'carpenter',
    'electrician',
    'plumber',
    'mason',
    'painter',
    'laborer',
    'operator',
    'other',
  ];

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _wageController = TextEditingController();
  final _notesController = TextEditingController();
  String _workerType = 'other';
  bool _loading = false;
  bool _prefilling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.workerId != null) {
      _prefill();
    }
  }

  Future<void> _prefill() async {
    setState(() => _prefilling = true);
    final worker = await ref
        .read(workerRepositoryProvider)
        .getWorker(widget.workerId!);
    if (worker != null && mounted) {
      setState(() {
        _nameController.text = worker.name;
        _phoneController.text = worker.phoneNumber;
        _wageController.text = worker.dailyWage.toStringAsFixed(2);
        _workerType = _workerTypes.contains(worker.workerType)
            ? worker.workerType
            : 'other';
        _notesController.text = worker.notes;
      });
    }
    if (mounted) {
      setState(() => _prefilling = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _wageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _fallbackRoute() {
    if (widget.workerId != null && widget.workerId!.isNotEmpty) {
      return AppRoutes.workerDetailPath(widget.workerId!);
    }
    return AppRoutes.workers;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    final wage = double.tryParse(_wageController.text.trim());
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    if (_nameController.text.trim().isEmpty || wage == null || wage <= 0) {
      setState(() => _error = l10n.t('nameAndValidWageRequired'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.workerId == null) {
        await ref
            .read(workerRepositoryProvider)
            .createWorker(
              workspaceId: workspaceId,
              userId: userId,
              name: _nameController.text.trim(),
              phoneNumber: _phoneController.text.trim(),
              dailyWage: wage,
              workerType: _workerType,
              notes: _notesController.text.trim(),
            );
      } else {
        await ref
            .read(workerRepositoryProvider)
            .updateWorker(
              workerId: widget.workerId!,
              name: _nameController.text.trim(),
              phoneNumber: _phoneController.text.trim(),
              dailyWage: wage,
              workerType: _workerType,
              notes: _notesController.text.trim(),
            );
      }
      if (mounted) {
        appNavigateBack(context, fallbackRoute: _fallbackRoute());
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
    final l10n = AppLocalizations.of(context);
    return AppBackScope(
      fallbackRoute: _fallbackRoute(),
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: widget.workerId == null
              ? l10n.t('addWorkerTitle')
              : l10n.t('editWorkerTitle'),
          fallbackRoute: _fallbackRoute(),
        ),
        body: _prefilling
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: l10n.t('workerName'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l10n.t('phoneNumber'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _wageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.t('dailyWage')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _workerType,
                    items: _workerTypes
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(l10n.workerTypeLabel(type)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _workerType = value ?? _workerType),
                    decoration: InputDecoration(
                      labelText: l10n.t('workerType'),
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
                            widget.workerId == null
                                ? l10n.t('saveWorker')
                                : l10n.t('updateWorker'),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
