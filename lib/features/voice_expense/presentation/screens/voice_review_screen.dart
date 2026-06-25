import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/utils/number_parser.dart';
import 'package:buildtrack_app/core/utils/thousands_separator_input_formatter.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/services/expense_save_service.dart';
import 'package:buildtrack_app/core/services/session_restore_service.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/firebase_functions_error_message.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
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
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  static const _allowedCurrencies = <String>['EGP', 'USD', 'SAR', 'AED'];
  static const _allowedCategories = <String>[
    'worker',
    'materials',
    'equipment',
    'transport',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    final parsed = widget.response.parsed;
    _amountController.text = parsed.amount == null
        ? ''
        : ThousandsSeparatorInputFormatter.formatInitial(
            parsed.amount.toString(),
          );
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

  Future<String?> _resolvedWorkspaceId() async {
    final currentWorkspaceId = ref.read(activeWorkspaceIdProvider);
    if (currentWorkspaceId != null && currentWorkspaceId.isNotEmpty) {
      return currentWorkspaceId;
    }

    final restored = await ref.read(sessionRestoreServiceProvider).restore();
    if (restored == null) {
      return null;
    }

    ref.read(activeUserIdProvider.notifier).state = restored.userId;
    ref.read(activeWorkspaceIdProvider.notifier).state = restored.workspaceId;
    return restored.workspaceId;
  }

  Future<String?> _workspaceIdFromSelectedProject() async {
    final projectId = _projectId;
    if (projectId == null || projectId.isEmpty) {
      return null;
    }
    final project = await ref
        .read(projectRepositoryProvider)
        .getProject(projectId);
    return project?.workspaceId;
  }

  Future<void> _saveConfirmed() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId =
        await _resolvedWorkspaceId() ?? await _workspaceIdFromSelectedProject();
    final amount = NumberParser.parseDouble(_amountController.text);
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
            date: _date,
          );
      if (!mounted) {
        return;
      }
      context.go(AppRoutes.projectExpensesPath(_projectId!));
    } on ExpenseSaveServiceException catch (e) {
      if (e.code == 'failed-precondition') {
        if (!mounted) {
          return;
        }
        context.push('${AppRoutes.subscriptionLimit}?limit=expensesPerMonth');
      } else if (mounted) {
        setState(() => _error = _messageForSaveError(e, l10n));
      }
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

  String _messageForSaveError(
    ExpenseSaveServiceException error,
    AppLocalizations l10n,
  ) {
    if (error.code == 'unauthenticated') {
      if (ref.read(firebaseAuthProvider).currentUser == null) {
        return l10n.t('pleaseLoginFirst');
      }
      final message = error.message.trim();
      return message.isEmpty ? l10n.t('unexpectedErrorTryAgain') : message;
    }

    final message = error.message.trim();
    return message.isEmpty ? l10n.t('unexpectedErrorTryAgain') : message;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parsed = widget.response.parsed;
    final confidence = widget.response.confidence;
    final defaultCurrency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
    if (_currency == 'EGP' &&
        (parsed.currency == null || parsed.currency!.isEmpty) &&
        defaultCurrency != 'EGP') {
      _currency = defaultCurrency;
    }
    return AppBackScope(
      fallbackRoute: AppRoutes.voiceExpense,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('reviewVoiceExpense'),
          fallbackRoute: AppRoutes.voiceExpense,
        ),
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
                          'amount': (confidence.amount * 100).toStringAsFixed(
                            0,
                          ),
                          'category': (confidence.category * 100)
                              .toStringAsFixed(0),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [ThousandsSeparatorInputFormatter()],
              decoration: InputDecoration(labelText: l10n.t('amount')),
            ),
            const SizedBox(height: 12),
            BelowDropdownField<String>(
              label: l10n.t('currencyLabel'),
              value: _currency,
              entries: _allowedCurrencies
                  .map(
                    (currency) =>
                        DropdownMenuEntry(value: currency, label: currency),
                  )
                  .toList(),
              onSelected: (value) {
                setState(() => _currency = value ?? _currency);
              },
            ),
            const SizedBox(height: 12),
            BelowDropdownField<String>(
              label: l10n.t('category'),
              value: _category,
              entries: _allowedCategories
                  .map(
                    (category) => DropdownMenuEntry(
                      value: category,
                      label: l10n.expenseCategoryLabel(category),
                    ),
                  )
                  .toList(),
              onSelected: (value) {
                setState(() => _category = value ?? _category);
              },
            ),
            const SizedBox(height: 12),
            BelowDropdownField<String>(
              label: l10n.t('project'),
              value: _projectId,
              entries: widget.projects
                  .map(
                    (project) => DropdownMenuEntry(
                      value: project.id,
                      label: project.name,
                    ),
                  )
                  .toList(),
              onSelected: (value) {
                setState(() => _projectId = value);
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
                if (picked != null) {
                  setState(() => _date = picked);
                }
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
                    onPressed: _saving
                        ? null
                        : () => appNavigateBack(
                            context,
                            fallbackRoute: AppRoutes.voiceExpense,
                          ),
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
      ),
    );
  }
}
