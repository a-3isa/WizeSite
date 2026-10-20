import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/core/utils/expense_category.dart';
import 'package:buildtrack_app/core/utils/thousands_separator_input_formatter.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_proposal.dart';
import 'package:buildtrack_app/features/expenses/presentation/widgets/expense_items_editor.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/services/expense_save_service.dart';
import 'package:buildtrack_app/core/services/session_restore_service.dart';
import 'package:buildtrack_app/core/services/sync_error_classifier.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/callable_error_message.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/voice_expense/data/voice_expense_repository.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
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
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _supplierController = TextEditingController();
  final _items = ExpenseItemsEditorController();
  String _currency = 'EGP';
  String _category = 'other';
  String? _projectId;
  String? _entityId;
  String _paymentStatus = PaymentStatuses.unpaid;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  static const _allowedCurrencies = <String>['EGP', 'USD', 'SAR', 'AED'];
  static const _allowedCategories = <String>[
    'worker',
    'materials',
    'equipment',
    'transport',
    'contractor',
    'storage',
    'rentals',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    final parsed = widget.response.parsed;
    final proposal = widget.response.proposal;
    _currency = _allowedCurrencies.contains(proposal?.currency)
        ? proposal!.currency
        : _allowedCurrencies.contains(parsed.currency)
        ? parsed.currency!
        : 'EGP';
    final parsedCategory = normalizeExpenseCategory(
      proposal?.category ?? parsed.category,
    );
    _category = _allowedCategories.contains(parsedCategory)
        ? parsedCategory
        : 'other';
    _projectId = _resolveInitialProjectId(parsed, proposal);
    if (proposal != null) {
      // Feature 005: the AI's title, items and any mentioned fields.
      _titleController.text = proposal.proposedTitle ?? '';
      _items.replaceAll(proposal.toDrafts());
      _supplierController.text = proposal.entityName ?? '';
      _entityId = proposal.entityId;
      if (const [
        PaymentStatuses.unpaid,
        PaymentStatuses.partial,
        PaymentStatuses.paid,
      ].contains(proposal.paymentStatus)) {
        _paymentStatus = proposal.paymentStatus!;
      }
      _date = proposal.parsedDate ?? _date;
    } else {
      // An older server: one row from the single parsed amount.
      _noteController.text = parsed.note ?? '';
      _items.replaceAll([
        ExpenseItemDraft(
          name: parsed.note ?? '',
          amountText: parsed.amount == null
              ? ''
              : ExpenseItemDraft.formatNumber(parsed.amount!),
        ),
      ]);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _supplierController.dispose();
    _items.dispose();
    super.dispose();
  }

  String? _resolveInitialProjectId(
    VoiceParsedExpense parsed,
    ExpenseProposal? proposal,
  ) {
    final proposed = proposal?.projectId;
    if (proposed != null && widget.projects.any((p) => p.id == proposed)) {
      return proposed;
    }
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
    if (!mounted) {
      return;
    }
    // Every item needs a name and a positive amount; AI-flagged rows must be
    // checked first (FR-007, FR-016).
    final amount = _items.validate() ? _items.total : null;
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
    final items = _items.toItemMaps();
    // FR-008: an empty title becomes the first item name.
    var title = _titleController.text.trim();
    if (title.isEmpty) {
      title = '${items.first['name'] ?? ''}'.trim();
    }
    final supplier = _supplierController.text.trim();

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
            items: items,
            description: title,
            entityId: supplier.isEmpty ? null : _entityId,
            entityName: supplier.isEmpty ? null : supplier,
            paymentStatus: _paymentStatus,
          );
      if (!mounted) {
        return;
      }
      context.go(AppRoutes.projectExpensesPath(_projectId!));
    } on ExpenseSaveServiceException catch (e) {
      if (SyncErrorClassifier.isQuotaLimitFailure(e)) {
        if (!mounted) {
          return;
        }
        context.push('${AppRoutes.subscriptionLimit}?limit=expensesPerMonth');
      } else if (mounted) {
        setState(() => _error = _messageForSaveError(e, l10n));
      }
    } on CallableClientException catch (e) {
      if (SyncErrorClassifier.isQuotaLimitFailure(e)) {
        if (!mounted) {
          return;
        }
        context.push('${AppRoutes.subscriptionLimit}?limit=expensesPerMonth');
      } else if (mounted) {
        setState(() => _error = callableErrorMessage(e, l10n));
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
    final t = context.tokens;
    final parsed = widget.response.parsed;
    final proposal = widget.response.proposal;
    final confidence = widget.response.confidence;
    final defaultCurrency =
        ref.watch(currentUserSettingsProvider).value?.defaultCurrency ?? 'EGP';
    if (_currency == 'EGP' &&
        (parsed.currency == null || parsed.currency!.isEmpty) &&
        defaultCurrency != 'EGP') {
      _currency = defaultCurrency;
    }
    return AppBackScope(
      fallbackRoute: AppRoutes.voiceExpense,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('reviewVoiceExpense'),
          fallbackRoute: AppRoutes.voiceExpense,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Transcript card: what was heard, plus source + confidence.
            BuildCard(
              elevated: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('transcript'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: t.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.response.transcript,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.t(
                      'sourceWithValue',
                      params: {'value': widget.response.source},
                    ),
                    style: TextStyle(fontSize: 12.5, color: t.textMuted),
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
                    style: TextStyle(fontSize: 12.5, color: t.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (proposal != null && proposal.totalMismatch) ...[
              _InfoBanner(
                key: const Key('qa_voice_review_total_mismatch'),
                message: l10n.t(
                  'statedTotalMismatch',
                  params: {
                    'stated': ThousandsSeparatorInputFormatter.formatInitial(
                      (proposal.statedTotal ?? 0).toStringAsFixed(2),
                    ),
                    'sum': ThousandsSeparatorInputFormatter.formatInitial(
                      proposal.itemsTotal.toStringAsFixed(2),
                    ),
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (proposal != null && proposal.multipleReceiptsSuspected) ...[
              _InfoBanner(
                key: const Key('qa_voice_review_multiple_receipts'),
                message: l10n.t('multipleReceiptsWarning'),
              ),
              const SizedBox(height: 12),
            ],
            // Title, items, then the fields shared by the whole receipt.
            BuildTextField(
              fieldKey: const Key('qa_voice_review_title'),
              label: l10n.t('expenseTitle'),
              controller: _titleController,
            ),
            const SizedBox(height: 16),
            ExpenseItemsEditor(
              key: const Key('qa_voice_review_items'),
              controller: _items,
              currency: _currency,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            SelectField(
              key: const Key('qa_voice_review_currency'),
              label: l10n.t('currencyLabel'),
              valueLabel: _currency,
              icon: Icons.payments_outlined,
              onTap: () => pickOption(
                context,
                title: l10n.t('currencyLabel'),
                selected: _currency,
                options: [
                  for (final currency in _allowedCurrencies)
                    (value: currency, label: currency),
                ],
                onSelected: (value) => setState(() => _currency = value),
              ),
            ),
            const SizedBox(height: 16),
            SelectField(
              key: const Key('qa_voice_review_category'),
              label: l10n.t('category'),
              valueLabel: l10n.expenseCategoryLabel(_category),
              icon: Icons.category_outlined,
              onTap: () => pickOption(
                context,
                title: l10n.t('category'),
                selected: _category,
                options: [
                  for (final category in _allowedCategories)
                    (
                      value: category,
                      label: l10n.expenseCategoryLabel(category),
                    ),
                ],
                onSelected: (value) => setState(() => _category = value),
              ),
            ),
            const SizedBox(height: 16),
            SelectField(
              key: const Key('qa_voice_review_project'),
              label: l10n.t('project'),
              valueLabel: _projectId == null
                  ? null
                  : _projectNameFromId(_projectId!),
              placeholder: l10n.t('selectProject'),
              icon: Icons.apartment_outlined,
              onTap: () => pickOption(
                context,
                title: l10n.t('project'),
                selected: _projectId,
                options: [
                  for (final project in widget.projects)
                    (value: project.id, label: project.name),
                ],
                onSelected: (value) => setState(() => _projectId = value),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.t(
                  'dateWithValue',
                  params: {'value': _date.toIso8601String().split('T').first},
                ),
                style: TextStyle(fontWeight: FontWeight.w600, color: t.text),
              ),
              trailing: Icon(Icons.calendar_today_outlined, color: t.accent),
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
            const SizedBox(height: 16),
            BuildTextField(
              fieldKey: const Key('qa_voice_review_supplier'),
              label: l10n.t('supplierNameOptional'),
              controller: _supplierController,
              // A typed name is a new supplier, not the AI-matched one.
              onChanged: (_) => _entityId = null,
            ),
            const SizedBox(height: 16),
            SelectField(
              key: const Key('qa_voice_review_payment_status'),
              label: l10n.t('paymentStatus'),
              valueLabel: l10n.paymentStatusLabel(_paymentStatus),
              icon: Icons.receipt_long_outlined,
              onTap: () => pickOption(
                context,
                title: l10n.t('paymentStatus'),
                selected: _paymentStatus,
                options: [
                  for (final status in const [
                    PaymentStatuses.unpaid,
                    PaymentStatuses.partial,
                    PaymentStatuses.paid,
                  ])
                    (value: status, label: l10n.paymentStatusLabel(status)),
                ],
                onSelected: (value) => setState(() => _paymentStatus = value),
              ),
            ),
            const SizedBox(height: 16),
            BuildTextField(
              key: const Key('qa_voice_review_notes'),
              label: l10n.t('notes'),
              controller: _noteController,
              maxLines: 3,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 20),
            if (_saving)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: BuildButton(
                      key: const Key('qa_voice_review_cancel'),
                      label: l10n.t('cancel'),
                      variant: BuildButtonVariant.outline,
                      size: BuildButtonSize.lg,
                      full: true,
                      onPressed: () => appNavigateBack(
                        context,
                        fallbackRoute: AppRoutes.voiceExpense,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BuildButton(
                      key: const Key('qa_voice_review_confirm'),
                      label: l10n.t('confirmAndSave'),
                      size: BuildButtonSize.lg,
                      full: true,
                      onPressed: _saveConfirmed,
                    ),
                  ),
                ],
              ),
            if (parsed.matchedProjectId == null &&
                parsed.matchedProjectName != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.t(
                  'detectedProjectName',
                  params: {'name': parsed.matchedProjectName ?? ''},
                ),
                style: TextStyle(fontSize: 12, color: t.textFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact banner for the top-level form error, tinted with the expense
/// (danger) semantic color. Matches the v2 `_ErrorBanner` pattern used on the
/// add-expense/add-payment screens.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.expenseSoft, borderRadius: t.radiusMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: t.expense),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: t.expense),
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-blocking notice about the AI proposal (total mismatch, several
/// receipts), tinted with the warning semantic color.
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.warningSoft, borderRadius: t.radiusMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: t.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: t.text)),
          ),
        ],
      ),
    );
  }
}
