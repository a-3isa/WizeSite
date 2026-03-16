import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/firebase_functions_error_message.dart';
import 'package:buildtrack_app/features/voice_expense/data/voice_expense_repository.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class VoiceReviewScreen extends ConsumerStatefulWidget {
  const VoiceReviewScreen({
    required this.response,
    required this.projects,
    super.key,
  });

  final VoiceExpenseParseResponse response;
  final List<VoiceProjectOption> projects;

  @override
  ConsumerState<VoiceReviewScreen> createState() => _VoiceReviewScreenState();
}

class _VoiceReviewScreenState extends ConsumerState<VoiceReviewScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _currency = 'EGP';
  String _category = 'other';
  String? _projectId;
  bool _saving = false;
  String? _error;

  static const _allowedCurrencies = <String>['EGP', 'USD', 'SAR', 'AED'];
  static const _allowedCategories = <String>[
    'labor',
    'materials',
    'equipment',
    'transport',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    final parsed = widget.response.parsed;
    _amountController.text = parsed.amount?.toString() ?? '';
    _noteController.text = parsed.note ?? '';
    _currency = _allowedCurrencies.contains(parsed.currency)
        ? parsed.currency!
        : 'EGP';
    _category = _allowedCategories.contains(parsed.category)
        ? parsed.category!
        : 'other';
    _projectId = _resolveInitialProjectId(parsed);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String? _resolveInitialProjectId(VoiceParsedExpense parsed) {
    if (parsed.matchedProjectId != null) {
      return parsed.matchedProjectId;
    }
    final matchedName = parsed.matchedProjectName?.trim().toLowerCase();
    if (matchedName == null || matchedName.isEmpty) {
      return null;
    }
    for (final project in widget.projects) {
      if (project.name.trim().toLowerCase() == matchedName) {
        return project.id;
      }
    }
    return null;
  }

  String _projectNameFromId(String projectId) {
    final matches = widget.projects.where((p) => p.id == projectId);
    if (matches.isEmpty) {
      return '';
    }
    return matches.first.name;
  }

  Future<void> _saveConfirmed() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final amount = double.tryParse(_amountController.text.trim());
    if (workspaceId == null || workspaceId.isEmpty) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    if (_projectId == null || _projectId!.isEmpty) {
      setState(() => _error = l10n.t('selectProjectRequired'));
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = l10n.t('amountMustBeGreaterThanZero'));
      return;
    }
    if (!_allowedCategories.contains(_category)) {
      setState(() => _error = l10n.t('selectValidCategory'));
      return;
    }
    if (!_allowedCurrencies.contains(_currency)) {
      setState(() => _error = l10n.t('selectValidCurrency'));
      return;
    }

    final projectName = _projectNameFromId(_projectId!);
    if (projectName.isEmpty) {
      setState(() => _error = l10n.t('selectedProjectInvalid'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(voiceExpenseRepositoryProvider)
          .saveConfirmedVoiceExpense(
            workspaceId: workspaceId,
            projectId: _projectId!,
            projectName: projectName,
            amount: amount,
            currency: _currency,
            category: _category,
            notes: _noteController.text.trim(),
            transcript: widget.response.transcript,
            source: widget.response.source,
            storagePath: widget.response.storagePath,
            date: DateTime.now(),
          );
      if (!mounted) {
        return;
      }
      context.go(AppRoutes.expenses);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        if (!mounted) {
          return;
        }
        context.push('${AppRoutes.subscriptionLimit}?limit=expensesPerMonth');
      } else if (mounted) {
        setState(() => _error = firebaseFunctionsErrorMessage(e, l10n));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.t('unexpectedErrorTryAgain'));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parsed = widget.response.parsed;
    final confidence = widget.response.confidence;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('reviewVoiceExpense'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('transcript'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(widget.response.transcript),
                  const SizedBox(height: 12),
                  Text(
                    l10n.t(
                      'sourceWithValue',
                      params: {'value': widget.response.source},
                    ),
                  ),
                  Text(
                    l10n.t(
                      'voiceConfidenceSummary',
                      params: {
                        'amount': (confidence.amount * 100).toStringAsFixed(0),
                        'category': (confidence.category * 100).toStringAsFixed(
                          0,
                        ),
                        'project': (confidence.project * 100).toStringAsFixed(
                          0,
                        ),
                        'overall': (confidence.overall * 100).toStringAsFixed(
                          0,
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.t('amount')),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _currency,
            decoration: InputDecoration(labelText: l10n.t('currencyLabel')),
            items: _allowedCurrencies
                .map(
                  (currency) =>
                      DropdownMenuItem(value: currency, child: Text(currency)),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _currency = value ?? _currency);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: InputDecoration(labelText: l10n.t('category')),
            items: _allowedCategories
                .map(
                  (category) => DropdownMenuItem(
                    value: category,
                    child: Text(l10n.expenseCategoryLabel(category)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _category = value ?? _category);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _projectId,
            decoration: InputDecoration(labelText: l10n.t('project')),
            items: widget.projects
                .map(
                  (project) => DropdownMenuItem(
                    value: project.id,
                    child: Text(project.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _projectId = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: InputDecoration(labelText: l10n.t('notes')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.t('cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _saveConfirmed,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.t('confirmAndSave')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (parsed.matchedProjectId == null &&
              parsed.matchedProjectName != null)
            Text(
              l10n.t(
                'detectedProjectName',
                params: {'name': parsed.matchedProjectName ?? ''},
              ),
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}
