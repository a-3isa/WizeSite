import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/utils/number_parser.dart';
import 'package:buildtrack_app/core/utils/thousands_separator_input_formatter.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/services/attachment_validation_service.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/presentation/widgets/entity_autocomplete_field.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

class AddPaymentScreen extends ConsumerStatefulWidget {
  const AddPaymentScreen({this.paymentId, this.projectId, super.key});

  final String? paymentId;
  final String? projectId;

  @override
  ConsumerState<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends ConsumerState<AddPaymentScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  String _method = 'cash';
  String _paymentStatus = PaymentStatuses.paid;
  String? _projectId;
  String? _entityId;
  String _entityName = '';
  DateTime _date = DateTime.now();
  bool _loading = false;
  bool _prefilling = false;
  String? _error;
  final _pickedFiles = <PlatformFile>[];
  final _attachments = <Attachment>[];

  @override
  void initState() {
    super.initState();
    if (widget.paymentId != null) {
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
      final payment = await ref
          .read(paymentRepositoryProvider)
          .getPayment(widget.paymentId!);
      if (payment != null && mounted) {
        setState(() {
          _projectId = payment.projectId;
          _amountController.text =
              ThousandsSeparatorInputFormatter.formatInitial(
                payment.amount.toStringAsFixed(2),
              );
          _method = payment.paymentMethod;
          _paymentStatus = payment.paymentStatus;
          _descriptionController.text = payment.description;
          _notesController.text = payment.notes;
          _entityId = payment.entityId;
          _entityName = payment.entityName;
          _date = payment.date;
          _attachments.clear();
          _attachments.addAll(payment.attachments);
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
    _amountController.dispose();
    _descriptionController.dispose();
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
    final validation = AttachmentValidationService.validatePickedFiles(
      result.files,
    );
    setState(() {
      _pickedFiles.addAll(validation.validFiles);
      if (validation.invalidMessages.isNotEmpty) {
        _error = validation.invalidMessages.join('\n');
      }
    });
  }

  String _fallbackRoute() {
    final projectId = _projectId ?? widget.projectId;
    if (projectId != null && projectId.isNotEmpty) {
      return AppRoutes.paymentsPath(projectId: projectId);
    }
    return AppRoutes.payments;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    final amount = NumberParser.parseDouble(_amountController.text);
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    if (_projectId == null || amount == null || amount < 0) {
      setState(() => _error = l10n.t('selectProjectAndValidAmount'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var queued = false;
      final attachmentsToSend = <Attachment>[..._attachments];
      if (_pickedFiles.isNotEmpty) {
        for (final file in _pickedFiles) {
          if (file.path == null) {
            continue;
          }
          final uploaded = await ref
              .read(storageUploadServiceProvider)
              .uploadAttachment(
                userId: userId,
                localFilePath: file.path!,
                fileName: file.name,
              );
          attachmentsToSend.add(
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
      }
      final resolvedEntity = await _resolveEntity(
        workspaceId: workspaceId,
        fallbackName: _entityName,
        type: 'other',
      );

      if (widget.paymentId == null) {
        try {
          await ref
              .read(entitlementGuardProvider)
              .ensureCanCreate(
                workspaceId: workspaceId,
                type: LimitType.paymentsPerMonth,
              );
        } on LimitExceeded {
          if (mounted) {
            context.push(AppRoutes.subscriptionLimitPath('paymentsPerMonth'));
          }
          return;
        }
        if (kDebugMode) {
          debugPrint(
            '[add_payment.save] create start workspaceId=$workspaceId '
            'userId=$userId projectId=$_projectId amount=$amount '
            'method=$_method date=${_date.toIso8601String()}',
          );
        }
        final result = await ref
            .read(paymentRepositoryProvider)
            .createPayment(
              workspaceId: workspaceId,
              userId: userId,
              projectId: _projectId!,
              amount: amount,
              date: _date,
              paymentMethod: _method,
              paymentStatus: _paymentStatus,
              description: _descriptionController.text.trim(),
              notes: _notesController.text.trim(),
              entityId: resolvedEntity.id,
              entityName: resolvedEntity.name,
              entityType: 'other',
              attachments: attachmentsToSend.isNotEmpty
                  ? attachmentsToSend
                  : null,
            );
        queued = result.queued;
        if (kDebugMode) {
          debugPrint(
            '[add_payment.save] create result queued=${result.queued} '
            'id=${result.id}',
          );
        }
      } else {
        await ref
            .read(paymentRepositoryProvider)
            .updatePayment(
              paymentId: widget.paymentId!,
              amount: amount,
              date: _date,
              paymentMethod: _method,
              paymentStatus: _paymentStatus,
              description: _descriptionController.text.trim(),
              notes: _notesController.text.trim(),
              entityId: resolvedEntity.id,
              entityName: resolvedEntity.name,
              entityType: 'other',
              attachments: attachmentsToSend,
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
          context.push('${AppRoutes.subscriptionLimit}?limit=paymentsPerMonth');
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

  Future<({String? id, String? name})> _resolveEntity({
    required String workspaceId,
    required String fallbackName,
    required String type,
  }) async {
    final name = (_entityName.isNotEmpty ? _entityName : fallbackName).trim();
    if (name.isEmpty) {
      return (id: _entityId, name: null);
    }
    if (_entityId != null && _entityId!.isNotEmpty) {
      return (id: _entityId, name: name);
    }
    final entity = await ref
        .read(entityRepositoryProvider)
        .ensureEntity(workspaceId: workspaceId, name: name, type: type);
    return (id: entity?.id ?? _entityId, name: entity?.name ?? name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final currency =
        ref.watch(currentUserSettingsProvider).value?.defaultCurrency ??
        'EGP';
    return AppBackScope(
      fallbackRoute: _fallbackRoute(),
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: appBackAppBar(
          context: context,
          title: widget.paymentId == null
              ? l10n.t('addPaymentTitle')
              : l10n.t('editPaymentTitle'),
          fallbackRoute: _fallbackRoute(),
        ),
        body: _prefilling
            ? const AppLoadingSkeleton(lineCount: 8)
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],
                  projectsAsync.whenStale(
                    data: (projects) {
                      final selected = projects.where(
                        (p) => p.id == _projectId,
                      );
                      return SelectField(
                        key: const Key('qa_add_payment_project'),
                        label: l10n.t('project'),
                        valueLabel: selected.isEmpty
                            ? null
                            : selected.first.name,
                        placeholder: l10n.t('selectProject'),
                        icon: Icons.apartment_outlined,
                        onTap: () => _pickOption(
                          context: context,
                          title: l10n.t('project'),
                          selected: _projectId,
                          options: [
                            for (final project in projects)
                              (value: project.id, label: project.name),
                          ],
                          onSelected: (value) =>
                              setState(() => _projectId = value),
                        ),
                      );
                    },
                    error: (e, _) => Text(appErrorMessage(l10n, e)),
                    loading: () => const AppLoadingSkeleton(
                      lineCount: 2,
                      padding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _AmountHero(
                    textFieldKey: const Key('qa_add_payment_amount'),
                    controller: _amountController,
                    color: t.income,
                    currency: currency,
                    label: l10n.t('amount'),
                  ),
                  const SizedBox(height: 16),
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
                    trailing: const Icon(Icons.calendar_today_outlined),
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
                  SelectField(
                    key: const Key('qa_add_payment_method'),
                    label: l10n.t('paymentMethod'),
                    valueLabel: l10n.paymentMethodLabel(_method),
                    icon: Icons.payments_outlined,
                    onTap: () => _pickOption(
                      context: context,
                      title: l10n.t('paymentMethod'),
                      selected: _method,
                      options: [
                        for (final method in const ['cash', 'bank', 'check'])
                          (
                            value: method,
                            label: l10n.paymentMethodLabel(method),
                          ),
                      ],
                      onSelected: (value) =>
                          setState(() => _method = value),
                    ),
                  ),
                  const SizedBox(height: 12),
                  EntityAutocompleteField(
                    workspaceId: workspaceId ?? '',
                    label: l10n.t('entityNameOptional'),
                    initialEntityId: _entityId,
                    initialEntityName: _entityName.isNotEmpty
                        ? _entityName
                        : null,
                    onChanged: (entityId, entityName) {
                      setState(() {
                        _entityId = entityId;
                        _entityName = entityName ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  BelowDropdownField<String>(
                    label: l10n.t('paymentStatus'),
                    value: _paymentStatus,
                    entries: [
                      DropdownMenuEntry(
                        value: PaymentStatuses.unpaid,
                        label: l10n.paymentStatusLabel(PaymentStatuses.unpaid),
                      ),
                      DropdownMenuEntry(
                        value: PaymentStatuses.partial,
                        label: l10n.paymentStatusLabel(PaymentStatuses.partial),
                      ),
                      DropdownMenuEntry(
                        value: PaymentStatuses.paid,
                        label: l10n.paymentStatusLabel(PaymentStatuses.paid),
                      ),
                    ],
                    onSelected: (value) => setState(
                      () => _paymentStatus = value ?? _paymentStatus,
                    ),
                  ),
                  const SizedBox(height: 12),
                  BuildTextField(
                    key: const Key('qa_add_payment_description'),
                    label: l10n.t('description'),
                    controller: _descriptionController,
                  ),
                  const SizedBox(height: 12),
                  BuildTextField(
                    key: const Key('qa_add_payment_notes'),
                    label: l10n.t('notes'),
                    controller: _notesController,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.t('attachments'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
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
                                color: t.expense,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: t.onAccent,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.attach_file_outlined,
                                ),
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
                                color: t.expense,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: t.onAccent,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.description_outlined,
                                ),
                                title: Text(entry.value.name),
                                subtitle: Text(entry.value.path ?? ''),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  BuildButton(
                    key: const Key('qa_add_payment_pick_attachments'),
                    label: l10n.t('selectAttachments'),
                    variant: BuildButtonVariant.soft,
                    icon: Icons.attach_file_outlined,
                    onPressed: _loading ? null : _pickAttachments,
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else
                    BuildButton(
                      key: const Key('qa_add_payment_save'),
                      label: widget.paymentId == null
                          ? l10n.t('savePayment')
                          : l10n.t('updatePayment'),
                      size: BuildButtonSize.lg,
                      full: true,
                      onPressed: _save,
                    ),
                ],
              ),
      ),
    );
  }
}

typedef _PickerOption = ({String value, String label});

/// Shows a bottom-sheet list of [options] and invokes [onSelected] with the
/// tapped value's `value`. Mirrors the v2 "picker" affordance used behind
/// [SelectField]s; kept private to this screen to avoid growing the shared
/// DS surface for a single-screen concern.
Future<void> _pickOption({
  required BuildContext context,
  required String title,
  required String? selected,
  required List<_PickerOption> options,
  required ValueChanged<String> onSelected,
}) async {
  final t = context.tokens;
  final result = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: t.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.rLg)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              for (final option in options)
                ListTile(
                  title: Text(
                    option.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  trailing: option.value == selected
                      ? Icon(Icons.check, color: t.accent)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option.value),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
  if (result != null) {
    onSelected(result);
  }
}

/// Compact banner for the top-level form error, tinted with the expense
/// (danger) semantic color.
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

/// Big, centered amount entry used at the top of the non-worker expense form
/// and the payment form. [color] carries the money semantic (expense red for
/// outflow, income green for inflow).
class _AmountHero extends StatelessWidget {
  const _AmountHero({
    required this.controller,
    required this.color,
    required this.currency,
    required this.label,
    this.textFieldKey,
  });

  final TextEditingController controller;
  final Color color;
  final String currency;
  final String label;
  final Key? textFieldKey;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BuildCard(
      elevated: true,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: textFieldKey,
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [ThousandsSeparatorInputFormatter()],
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: color,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: '0.00',
              hintStyle: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: t.textFaint,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            currency,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
