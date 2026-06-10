import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/attachment_tile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

class DomainAccountingRecordsScreen extends ConsumerWidget {
  const DomainAccountingRecordsScreen({
    required this.titleKey,
    required this.collectionName,
    required this.ownerIdField,
    required this.ownerNameField,
    required this.ownerId,
    required this.ownerName,
    this.projectId,
    super.key,
  });

  final String titleKey;
  final String collectionName;
  final String ownerIdField;
  final String ownerNameField;
  final String ownerId;
  final String ownerName;
  final String? projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final query = workspaceId == null
        ? null
        : ref
              .watch(firestoreProvider)
              .collection(collectionName)
              .where('workspaceId', isEqualTo: workspaceId)
              .where(ownerIdField, isEqualTo: ownerId)
              .orderBy('date', descending: true)
              .limit(50);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t(titleKey))),
      floatingActionButton: workspaceId == null
          ? null
          : FloatingActionButton(
              onPressed: () => _showEntryForm(context, ref, workspaceId),
              child: const Icon(Icons.add),
            ),
      body: workspaceId == null
          ? Center(child: Text(l10n.t('pleaseLoginFirst')))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query!.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final records = snapshot.data!.docs
                    .map((doc) => _AccountingRecord(doc.id, doc.data()))
                    .toList(growable: false);
                if (records.isEmpty) {
                  return Center(child: Text(l10n.t('noDataYet')));
                }
                final total = records.fold<double>(
                  0,
                  (runningTotal, record) => runningTotal + record.amount,
                );
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
                                  final url =
                                      attachment.downloadUrl ??
                                      attachment.localPath ??
                                      '';
                                  if (url.isNotEmpty) {
                                    unawaited(
                                      launchUrlString(
                                        url,
                                        mode: LaunchMode.externalApplication,
                                      ),
                                    );
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
    var paymentMethod = 'cash';
    var paymentStatus = 'paid';
    var date = DateTime.now();

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
                    keyboardType: TextInputType.number,
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
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      final amount =
                          double.tryParse(amountController.text.trim()) ?? 0;
                      if (amount <= 0) {
                        return;
                      }
                      final doc = ref
                          .read(firestoreProvider)
                          .collection(collectionName)
                          .doc();
                      await doc.set({
                        'workspaceId': workspaceId,
                        'projectId': projectId ?? '',
                        ownerIdField: ownerId,
                        ownerNameField: ownerName,
                        'description': descriptionController.text.trim(),
                        'amount': amount,
                        'date': Timestamp.fromDate(date),
                        'paymentMethod': paymentMethod,
                        'paymentStatus': paymentStatus,
                        'notes': notesController.text.trim(),
                        'attachments': const [],
                        'createdAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
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
    notesController.dispose();
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
