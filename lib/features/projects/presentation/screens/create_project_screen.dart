import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CreateProjectScreen extends ConsumerStatefulWidget {
  const CreateProjectScreen({this.projectId, super.key});

  final String? projectId;

  @override
  ConsumerState<CreateProjectScreen> createState() =>
      _CreateProjectScreenState();
}

class _CreateProjectScreenState extends ConsumerState<CreateProjectScreen> {
  final _nameController = TextEditingController();
  final _clientController = TextEditingController();
  final _contractController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();
  double _completion = 0;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  String _status = 'active';
  bool _loading = false;
  bool _prefilling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.projectId != null) {
      _prefill();
    }
  }

  Future<void> _prefill() async {
    setState(() => _prefilling = true);
    final project = await ref
        .read(projectRepositoryProvider)
        .getProject(widget.projectId!);
    if (project != null && mounted) {
      setState(() {
        _nameController.text = project.name;
        _clientController.text = project.clientName;
        _contractController.text = project.contractValue.toStringAsFixed(2);
        _completion = project.completionPercentage;
        _status = project.status;
      });
    }
    if (mounted) {
      setState(() => _prefilling = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientController.dispose();
    _contractController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    if (workspaceId == null || userId == null) {
      setState(() => _error = 'Please login first.');
      return;
    }

    final contract = double.tryParse(_contractController.text.trim());
    if (_nameController.text.trim().isEmpty ||
        contract == null ||
        contract <= 0) {
      setState(() => _error = 'Please fill required fields.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (widget.projectId == null) {
        await ref
            .read(projectRepositoryProvider)
            .createProject(
              workspaceId: workspaceId,
              userId: userId,
              name: _nameController.text.trim(),
              clientName: _clientController.text.trim(),
              contractValue: contract,
              startDate: _startDate,
              expectedEndDate: _endDate,
              location: _locationController.text.trim(),
              description: _descriptionController.text.trim(),
              budgetLimit: double.tryParse(_budgetController.text.trim()),
              completionPercentage: _completion,
            );
      } else {
        await ref
            .read(projectRepositoryProvider)
            .updateProject(
              projectId: widget.projectId!,
              name: _nameController.text.trim(),
              clientName: _clientController.text.trim(),
              contractValue: contract,
              startDate: _startDate,
              expectedEndDate: _endDate,
              location: _locationController.text.trim(),
              description: _descriptionController.text.trim(),
              budgetLimit: double.tryParse(_budgetController.text.trim()),
              completionPercentage: _completion,
              status: _status,
            );
      }
      if (mounted) {
        context.go(AppRoutes.projects);
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        if (mounted) {
          context.push('${AppRoutes.subscriptionLimit}?limit=activeProjects');
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

  Future<void> _pickDate({required bool isStart}) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: isStart ? _startDate : (_endDate ?? DateTime.now()),
    );
    if (date == null) {
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = date;
      } else {
        _endDate = date;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.projectId == null ? 'Create Project' : 'Edit Project',
        ),
      ),
      body: _prefilling
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Project Name *',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientController,
                  decoration: const InputDecoration(labelText: 'Client Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contractController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Contract Value *',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _locationController,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _budgetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Budget Limit'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'paused', child: Text('Paused')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completed'),
                    ),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('Cancelled'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'active'),
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Start Date: ${_startDate.toLocal().toIso8601String().split('T').first}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => _pickDate(isStart: true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _endDate == null
                        ? 'Expected End Date: Optional'
                        : 'Expected End Date: ${_endDate!.toLocal().toIso8601String().split('T').first}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => _pickDate(isStart: false),
                ),
                const SizedBox(height: 12),
                Text('Completion: ${_completion.toInt()}%'),
                Slider(
                  min: 0,
                  max: 100,
                  value: _completion,
                  onChanged: (value) => setState(() => _completion = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.projectId == null
                              ? 'Save Project'
                              : 'Update Project',
                        ),
                ),
              ],
            ),
    );
  }
}
