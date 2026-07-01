import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/utils/number_parser.dart';
import 'package:buildtrack_app/core/utils/safe_external_url.dart';
import 'package:buildtrack_app/core/utils/thousands_separator_input_formatter.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/attachment_tile.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_record_draft.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_save_adapter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef DomainAccountingSave =
    Future<void> Function(DomainAccountingRecordDraft draft);

typedef DomainAccountingHeaderBuilder =
    Widget? Function(BuildContext context, WidgetRef ref, String workspaceId);

class DomainAccountingRecordsScreen extends ConsumerWidget {
  const DomainAccountingRecordsScreen({
    required this.titleKey,
    required this.collectionName,
    required this.ownerIdField,
    required this.ownerNameField,
    required this.ownerId,
    required this.ownerName,
    this.projectId,
    this.onSave,
    this.headerBuilder,
    this.showPaidAmountField = false,
    super.key,
  });

  final String titleKey;
  final String collectionName;
  final String ownerIdField;
  final String ownerNameField;
  final String ownerId;
  final String ownerName;
  final String? projectId;
  final DomainAccountingSave? onSave;
  final DomainAccountingHeaderBuilder? headerBuilder;
  final bool showPaidAmountField;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final roleAsync = ref.watch(currentAccountingRoleProvider);
    final role = roleAsync.value;
    final canAccessAccounting =
        roleAsync.hasValue && ref.watch(canAccessAccountingProvider(role));
    final roleIsLoading = workspaceId != null && roleAsync.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t(titleKey))),
      floatingActionButton: workspaceId == null || !canAccessAccounting
          ? null
          : FloatingActionButton(
              onPressed: () => _showEntryForm(context, ref, workspaceId),
              child: const Icon(Icons.add),
            ),
      body: workspaceId == null
          ? Center(child: Text(l10n.t('pleaseLoginFirst')))
          : roleIsLoading
          ? const AppLoadingSkeleton()
          : !canAccessAccounting
          ? _DeniedAccountingState(message: l10n.t('reportAccessDenied'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ref
                  .watch(firestoreProvider)
                  .collection(collectionName)
                  .where('workspaceId', isEqualTo: workspaceId)
                  .where(ownerIdField, isEqualTo: ownerId)
                  .orderBy('date', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: AppRecoverableError(
                      message: appErrorMessage(l10n, snapshot.error),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const AppLoadingSkeleton(lineCount: 6);
                }
                final records = snapshot.data!.docs
                    .map((doc) => _AccountingRecord(doc.id, doc.data()))
                    .toList(growable: false);
                final header = headerBuilder?.call(context, ref, workspaceId);
                if (records.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (header != null) ...[
                        header,
                        const SizedBox(height: 8),
                      ],
                      AppEmptyState(message: l10n.t('noDataYet')),
                    ],
                  );
                }
                final total = records.fold<double>(
                  0,
                  (runningTotal, record) => runningTotal + record.amount,
                );
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (header != null) ...[header, const SizedBox(height: 8)],
                    Card(
                      child: ListTile(
                        title: Text(l10n.t('totalExpenses')),
                        trailing: Text(Formatters.money(total)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...records.map(
                      (record) => Card(
                        child: ExpansionTile(
                          title: Text(
                            record.description.isEmpty
                                ? ownerName
                                : record.description,
                          ),
                          subtitle: Text(
                            '${record.date.toIso8601String().split('T').first} • '
                            '${record.attachments.length} ${l10n.t('attachments')}',
                          ),
                          trailing: Text(Formatters.money(record.amount)),
                          childrenPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                l10n.paymentStatusLabel(record.paymentStatus),
                              ),
                            ),
                            if (record.notes.isNotEmpty)
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(record.notes),
                              ),
                            ...record.attachments.map(
                              (attachment) => AttachmentTile(
                                attachment: attachment,
                                onOpen: () {
                                  final url = attachment.downloadUrl ?? '';
                                  if (url.isNotEmpty) {
                                    unawaited(launchSafeExternalUrl(url));
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _showEntryForm(
    BuildContext context,
    WidgetRef ref,
    String workspaceId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final paidAmountController = TextEditingController();
    var paymentMethod = 'cash';
    var paymentStatus = 'paid';
    var date = DateTime.now();
    String? formError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    l10n.t(titleKey),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: l10n.t('description'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [ThousandsSeparatorInputFormatter()],
                    decoration: InputDecoration(labelText: l10n.t('amount')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: InputDecoration(
                      labelText: l10n.t('paymentMethod'),
                    ),
                    items: ['cash', 'bank', 'check']
                        .map(
                          (method) => DropdownMenuItem(
                            value: method,
                            child: Text(l10n.paymentMethodLabel(method)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setSheetState(
                      () => paymentMethod = value ?? paymentMethod,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: paymentStatus,
                    decoration: InputDecoration(
                      labelText: l10n.t('paymentStatus'),
                    ),
                    items: ['paid', 'partial', 'unpaid']
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(l10n.paymentStatusLabel(status)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setSheetState(
                      () => paymentStatus = value ?? paymentStatus,
                    ),
                  ),
                  if (showPaidAmountField && paymentStatus == 'partial') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: paidAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [
                        ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.t('workerPaidAmountLabel'),
                      ),
                    ),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l10n.t(
                        'dateWithValue',
                        params: {
                          'value': date.toIso8601String().split('T').first,
                        },
                      ),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: date,
                      );
                      if (picked != null) {
                        setSheetState(() => date = picked);
                      }
                    },
                  ),
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: l10n.t('notes')),
                  ),
                  if (formError != null) ...[
                    const SizedBox(height: 12),
                    Text(formError!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      final amount =
                          NumberParser.parseDouble(amountController.text) ?? 0;
                      if (amount <= 0) {
                        return;
                      }
                      final paidAmount =
                          paidAmountController.text.trim().isEmpty
                          ? null
                          : NumberParser.parseDouble(paidAmountController.text);
                      try {
                        final draft = DomainAccountingRecordDraft(
                          workspaceId: workspaceId,
                          projectId: projectId ?? '',
                          ownerIdField: ownerIdField,
                          ownerNameField: ownerNameField,
                          ownerId: ownerId,
                          ownerName: ownerName,
                          description: descriptionController.text.trim(),
                          amount: amount,
                          date: date,
                          paymentMethod: paymentMethod,
                          paymentStatus: paymentStatus,
                          paidAmount: paidAmount,
                          notes: notesController.text.trim(),
                        );
                        await (onSave ??
                            (draft) => ref
                                .read(domainAccountingSaveAdapterProvider)
                                .save(
                                  collectionName: collectionName,
                                  draft: draft,
                                ))(draft);
                      } catch (error) {
                        setSheetState(() {
                          formError =
                              error is DomainAccountingValidationException
                              ? l10n.t(error.messageKey)
                              : appErrorMessage(l10n, error);
                        });
                        return;
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(l10n.t('save')),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    descriptionController.dispose();
    amountController.dispose();
    paidAmountController.dispose();
    notesController.dispose();
  }
}

class _DeniedAccountingState extends StatelessWidget {
  const _DeniedAccountingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AppRecoverableError(message: message),
      ),
    );
  }
}

class _AccountingRecord {
  _AccountingRecord(this.id, Map<String, dynamic> map)
    : description = '${map['description'] ?? ''}',
      amount = (map['amount'] as num?)?.toDouble() ?? 0,
      date = _parseDate(map['date']),
      paymentStatus = '${map['paymentStatus'] ?? 'paid'}',
      notes = '${map['notes'] ?? ''}',
      attachments = Attachment.listFromDynamic(map['attachments']);

  final String id;
  final String description;
  final double amount;
  final DateTime date;
  final String paymentStatus;
  final String notes;
  final List<Attachment> attachments;
}

DateTime _parseDate(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is Timestamp) return raw.toDate();
  if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
  return DateTime.now();
}
