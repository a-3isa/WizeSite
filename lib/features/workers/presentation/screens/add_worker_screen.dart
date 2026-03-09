import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddWorkerScreen extends ConsumerStatefulWidget {
  const AddWorkerScreen({this.workerId, super.key});

  final String? workerId;

  @override
  ConsumerState<AddWorkerScreen> createState() => _AddWorkerScreenState();
}

class _AddWorkerScreenState extends ConsumerState<AddWorkerScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _wageController = TextEditingController();
  final _typeController = TextEditingController();
  final _notesController = TextEditingController();
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
        _typeController.text = worker.workerType;
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
    _typeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    final wage = double.tryParse(_wageController.text.trim());
    if (workspaceId == null || userId == null) {
      setState(() => _error = 'Please login first.');
      return;
    }
    if (_nameController.text.trim().isEmpty || wage == null || wage <= 0) {
      setState(() => _error = 'Name and valid daily wage are required.');
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
              workerType: _typeController.text.trim(),
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
              workerType: _typeController.text.trim(),
              notes: _notesController.text.trim(),
            );
      }
      if (mounted) {
        context.pop();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workerId == null ? 'Add Worker' : 'Edit Worker'),
      ),
      body: _prefilling
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Worker Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _wageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Daily Wage'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _typeController,
                  decoration: const InputDecoration(labelText: 'Worker Type'),
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
                          widget.workerId == null
                              ? 'Save Worker'
                              : 'Update Worker',
                        ),
                ),
              ],
            ),
    );
  }
}
