import 'dart:async';
import 'dart:math';

import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceExpenseDraft {
  const VoiceExpenseDraft({
    required this.projectId,
    required this.category,
    required this.amount,
    required this.notes,
  });

  final String projectId;
  final String category;
  final double amount;
  final String notes;
}

class VoiceExpenseParserService {
  const VoiceExpenseParserService();

  VoiceExpenseDraft? parse({
    required String transcript,
    required List<Project> projects,
  }) {
    final normalized = transcript.toLowerCase();
    if (normalized.trim().isEmpty) {
      return null;
    }

    final amountExp = RegExp(r'(\d+(\.\d+)?)');
    final amountMatch = amountExp.firstMatch(normalized);
    final amount = double.tryParse(amountMatch?.group(1) ?? '');
    if (amount == null) {
      return null;
    }

    final categories = <String, List<String>>{
      'labor': ['labor', 'عمال', 'نجارة', 'carpentry', 'worker'],
      'materials': ['materials', 'مواد', 'اسمنت', 'cement', 'steel'],
      'equipment': ['equipment', 'معدات'],
      'transport': ['transport', 'نقل', 'diesel', 'fuel'],
      'other': ['other', 'أخرى'],
    };

    String category = 'other';
    for (final entry in categories.entries) {
      if (entry.value.any(normalized.contains)) {
        category = entry.key;
        break;
      }
    }

    Project? chosenProject;
    var best = 0;
    for (final project in projects) {
      final name = project.name.toLowerCase();
      final score = _overlap(name, normalized);
      if (score > best) {
        best = score;
        chosenProject = project;
      }
    }
    if (chosenProject == null) {
      return null;
    }

    return VoiceExpenseDraft(
      projectId: chosenProject.id,
      category: category,
      amount: amount,
      notes: transcript.trim(),
    );
  }

  int _overlap(String a, String b) {
    final parts = a.split(' ').where((x) => x.trim().isNotEmpty).toList();
    return parts.where((part) => b.contains(part)).length + Random().nextInt(2);
  }
}

class VoiceExpenseScreen extends ConsumerStatefulWidget {
  const VoiceExpenseScreen({super.key});

  @override
  ConsumerState<VoiceExpenseScreen> createState() => _VoiceExpenseScreenState();
}

class _VoiceExpenseScreenState extends ConsumerState<VoiceExpenseScreen> {
  final _speech = SpeechToText();
  final _parser = const VoiceExpenseParserService();
  String _transcript = '';
  VoiceExpenseDraft? _draft;
  bool _isListening = false;
  bool _saving = false;
  String? _error;
  final DateTime _expenseDate = DateTime.now();

  Future<void> _toggleRecording(List<Project> projects) async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize();
    if (!available) {
      setState(() => _error = 'Speech not available on this device.');
      return;
    }
    setState(() {
      _error = null;
      _isListening = true;
      _draft = null;
      _transcript = '';
    });
    await _speech.listen(
      localeId: 'ar_EG',
      onResult: (res) {
        setState(() {
          _transcript = res.recognizedWords;
          _draft = _parser.parse(transcript: _transcript, projects: projects);
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
    );

    unawaited(
      Future<void>.delayed(const Duration(seconds: 30), () {
        if (mounted) {
          setState(() => _isListening = false);
        }
      }),
    );
  }

  Future<void> _saveDraft() async {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    if (workspaceId == null || userId == null) {
      setState(() => _error = 'Please login first.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(functionsProvider)
          .httpsCallable('createExpenseWithQuota')
          .call({
            'workspaceId': workspaceId,
            'userId': userId,
            'projectId': draft.projectId,
            'category': draft.category,
            'amount': draft.amount,
            'date': _expenseDate.toIso8601String(),
            'notes': draft.notes,
          });
      if (mounted) {
        context.go(AppRoutes.dashboard);
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        if (mounted) {
          context.push('${AppRoutes.subscriptionLimit}?limit=expensesPerMonth');
        }
      } else {
        setState(() => _error = e.message ?? e.code);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Expense Entry')),
      body: projectsAsync.when(
        data: (projects) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Tap the microphone and speak naturally.\nExample: "Paid 1500 for carpentry labor in Villa Project"',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Center(
              child: IconButton.filledTonal(
                style: IconButton.styleFrom(minimumSize: const Size(72, 72)),
                onPressed: () => _toggleRecording(projects),
                icon: Icon(_isListening ? Icons.stop : Icons.mic, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              readOnly: true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Transcript'),
              controller: TextEditingController(text: _transcript),
            ),
            const SizedBox(height: 16),
            if (_draft != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Parsed Result',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Project: ${_projectName(projects, _draft!.projectId)}',
                      ),
                      Text('Category: ${_draft!.category}'),
                      Text('Amount: ${_draft!.amount}'),
                      Text('Notes: ${_draft!.notes}'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving ? null : _saveDraft,
                              child: _saving
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Confirm'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() => _draft = null),
                              child: const Text('Edit'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  String _projectName(List<Project> projects, String id) {
    final match = projects.where((p) => p.id == id);
    return match.isEmpty ? 'Unknown Project' : match.first.name;
  }
}
