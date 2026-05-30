import 'dart:async';

import 'package:buildtrack_app/core/models/accounting_summary.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final entityAggregationsProvider =
    StreamProvider.family<List<EntitySummary>, String>((ref, workspaceId) {
      final firestore = ref.watch(firestoreProvider);
      final queue = ref.watch(offlineActionQueueProvider);

      final summaryStream = firestore
          .collection('entity_summaries')
          .where('workspaceId', isEqualTo: workspaceId)
          .orderBy('latestTransactionDate', descending: true)
          .limit(100)
          .snapshots();
      final workerAccountingStream = firestore
          .collection('worker_accounting_records')
          .where('workspaceId', isEqualTo: workspaceId)
          .limit(100)
          .snapshots();
      final contractorAccountingStream = firestore
          .collection('contractor_accounting_records')
          .where('workspaceId', isEqualTo: workspaceId)
          .limit(100)
          .snapshots();
      final equipmentAccountingStream = firestore
          .collection('equipment_accounting_records')
          .where('workspaceId', isEqualTo: workspaceId)
          .limit(100)
          .snapshots();
      final transportAccountingStream = firestore
          .collection('transport_provider_accounting_records')
          .where('workspaceId', isEqualTo: workspaceId)
          .limit(100)
          .snapshots();
      final actionStream = queue.watch();

      return Stream.multi((controller) {
        QuerySnapshot<Map<String, dynamic>>? latestSummaries;
        QuerySnapshot<Map<String, dynamic>>? latestWorkerRecords;
        QuerySnapshot<Map<String, dynamic>>? latestContractorRecords;
        QuerySnapshot<Map<String, dynamic>>? latestEquipmentRecords;
        QuerySnapshot<Map<String, dynamic>>? latestTransportRecords;
        List<OfflineAction>? latestActions;

        void emitIfReady() {
          if (latestSummaries == null ||
              latestWorkerRecords == null ||
              latestContractorRecords == null ||
              latestEquipmentRecords == null ||
              latestTransportRecords == null ||
              latestActions == null) {
            return;
          }
          controller.add(
            _buildEntitySummaries(
              latestSummaries!,
              latestActions!,
              domainSnapshots: [
                _DomainSnapshot(latestWorkerRecords!, 'worker'),
                _DomainSnapshot(latestContractorRecords!, 'contractor'),
                _DomainSnapshot(latestEquipmentRecords!, 'equipment'),
                _DomainSnapshot(latestTransportRecords!, 'transport'),
              ],
            ),
          );
        }

        final summarySub = summaryStream.listen((snapshot) {
          latestSummaries = snapshot;
          emitIfReady();
        }, onError: controller.addError);

        final actionSub = actionStream.listen((actions) {
          latestActions = actions;
          emitIfReady();
        }, onError: controller.addError);
        final workerSub = workerAccountingStream.listen((snapshot) {
          latestWorkerRecords = snapshot;
          emitIfReady();
        }, onError: controller.addError);
        final contractorSub = contractorAccountingStream.listen((snapshot) {
          latestContractorRecords = snapshot;
          emitIfReady();
        }, onError: controller.addError);
        final equipmentSub = equipmentAccountingStream.listen((snapshot) {
          latestEquipmentRecords = snapshot;
          emitIfReady();
        }, onError: controller.addError);
        final transportSub = transportAccountingStream.listen((snapshot) {
          latestTransportRecords = snapshot;
          emitIfReady();
        }, onError: controller.addError);

        controller.onCancel = () async {
          await summarySub.cancel();
          await actionSub.cancel();
          await workerSub.cancel();
          await contractorSub.cancel();
          await equipmentSub.cancel();
          await transportSub.cancel();
        };
      });
    });

class EntitySummary {
  EntitySummary({
    required this.entityId,
    required this.entityName,
    required this.entityType,
    this.totalExpenses = 0,
    this.totalPayments = 0,
    this.transactionCount = 0,
    this.attachmentCount = 0,
    this.latestTransaction,
    Map<String, double>? categoryBreakdown,
    Map<String, double>? paymentMethodBreakdown,
  }) {
    if (categoryBreakdown != null) {
      this.categoryBreakdown.addAll(categoryBreakdown);
    }
    if (paymentMethodBreakdown != null) {
      this.paymentMethodBreakdown.addAll(paymentMethodBreakdown);
    }
  }

  final String entityId;
  final String entityName;
  final String entityType;
  double totalExpenses;
  double totalPayments;
  int transactionCount;
  int attachmentCount;
  DateTime? latestTransaction;
  final Map<String, double> categoryBreakdown = {};
  final Map<String, double> paymentMethodBreakdown = {};

  double get net => totalPayments - totalExpenses;
}

class _DomainSnapshot {
  const _DomainSnapshot(this.snapshot, this.entityType);

  final QuerySnapshot<Map<String, dynamic>> snapshot;
  final String entityType;
}

List<EntitySummary> _buildEntitySummaries(
  QuerySnapshot<Map<String, dynamic>> summariesSnapshot,
  List<OfflineAction> actions, {
  List<_DomainSnapshot> domainSnapshots = const [],
}) {
  final summaries = <String, EntitySummary>{};

  void addSummary({
    required String key,
    required String name,
    required String type,
    required double expense,
    required double payment,
    required int transactionCount,
    required int attachments,
    required DateTime? date,
    Map<String, double> categoryBreakdown = const {},
    Map<String, double> paymentMethodBreakdown = const {},
  }) {
    final summary = summaries.putIfAbsent(
      key,
      () => EntitySummary(entityId: key, entityName: name, entityType: type),
    );
    summary.totalExpenses += expense;
    summary.totalPayments += payment;
    summary.transactionCount += transactionCount;
    summary.attachmentCount += attachments;
    _mergeBreakdown(summary.categoryBreakdown, categoryBreakdown);
    _mergeBreakdown(summary.paymentMethodBreakdown, paymentMethodBreakdown);
    if (date != null) {
      if (summary.latestTransaction == null ||
          date.isAfter(summary.latestTransaction!)) {
        summary.latestTransaction = date;
      }
    }
  }

  for (final doc in summariesSnapshot.docs) {
    final accountingSummary = EntityAccountingSummary.fromMap(doc.data());
    final key = accountingSummary.entityId.isNotEmpty
        ? accountingSummary.entityId
        : doc.id;
    addSummary(
      key: key,
      name: accountingSummary.entityName.isNotEmpty
          ? accountingSummary.entityName
          : key,
      type: accountingSummary.entityType.isNotEmpty
          ? accountingSummary.entityType
          : 'vendor',
      expense: accountingSummary.totalExpenses,
      payment: accountingSummary.totalPayments,
      transactionCount: accountingSummary.transactionCount,
      attachments: accountingSummary.attachmentCount,
      date: accountingSummary.latestTransactionDate,
      categoryBreakdown: accountingSummary.categoryBreakdown,
      paymentMethodBreakdown: accountingSummary.paymentMethodBreakdown,
    );
  }

  for (final domainSnapshot in domainSnapshots) {
    for (final doc in domainSnapshot.snapshot.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final entityId = _domainEntityId(data, domainSnapshot.entityType);
      final entityName = _domainEntityName(data, domainSnapshot.entityType);
      final category = _categoryForDomain(domainSnapshot.entityType);
      final paymentMethod = '${data['paymentMethod'] ?? ''}'.trim();
      addSummary(
        key: entityId,
        name: entityName,
        type: domainSnapshot.entityType,
        expense: amount,
        payment: 0,
        transactionCount: 1,
        attachments: (data['attachments'] as List?)?.length ?? 0,
        date: _parseDate(data['date']),
        categoryBreakdown: {category: amount},
        paymentMethodBreakdown: paymentMethod.isEmpty
            ? const {}
            : {paymentMethod: amount},
      );
    }
  }

  for (final action in actions) {
    if (!_isPendingCreate(action)) {
      continue;
    }
    final payload = action.payload;
    final key = _recordEntityKey(payload);
    final amount = ((payload['amount'] as num?)?.toDouble() ?? 0);
    final attachments = (payload['attachments'] as List?)?.length ?? 0;
    addSummary(
      key: key,
      name: _recordEntityName(payload, key),
      type: _recordEntityType(payload),
      expense: action.type == OfflineActionTypes.createExpense ? amount : 0,
      payment: action.type == OfflineActionTypes.createPayment ? amount : 0,
      transactionCount: 1,
      attachments: attachments,
      date: _parseDate(payload['date']) ?? action.createdAt,
    );
  }

  return summaries.values.toList()..sort((a, b) {
    final dateCompare = (b.latestTransaction ?? DateTime(0)).compareTo(
      a.latestTransaction ?? DateTime(0),
    );
    if (dateCompare != 0) {
      return dateCompare;
    }
    return (b.totalExpenses + b.totalPayments).compareTo(
      a.totalExpenses + a.totalPayments,
    );
  });
}

void _mergeBreakdown(Map<String, double> target, Map<String, double> source) {
  for (final entry in source.entries) {
    target[entry.key] = (target[entry.key] ?? 0) + entry.value;
  }
}

String _domainEntityId(Map<String, dynamic> data, String entityType) {
  final idKey = entityType == 'worker'
      ? 'workerId'
      : entityType == 'contractor'
          ? 'contractorId'
          : 'providerId';
  final value = '${data[idKey] ?? ''}'.trim();
  return value.isEmpty ? 'unassigned' : value;
}

String _domainEntityName(Map<String, dynamic> data, String entityType) {
  final nameKey = entityType == 'worker'
      ? 'workerName'
      : entityType == 'contractor'
          ? 'contractorName'
          : 'providerName';
  final value = '${data[nameKey] ?? ''}'.trim();
  return value.isEmpty ? 'Unassigned' : value;
}

String _categoryForDomain(String entityType) {
  return switch (entityType) {
    'worker' => 'labor',
    'contractor' => 'contractors',
    'equipment' => 'equipment',
    'transport' => 'transport',
    _ => 'other',
  };
}

bool _isPendingCreate(OfflineAction action) {
  return (action.type == OfflineActionTypes.createExpense ||
          action.type == OfflineActionTypes.createPayment) &&
      action.status != OfflineActionStatus.synced &&
      action.status != OfflineActionStatus.deadLetter;
}

String _recordEntityKey(Map<String, dynamic> data) {
  final entityId = '${data['entityId'] ?? ''}'.trim();
  if (entityId.isNotEmpty) {
    return entityId;
  }
  final entityName = '${data['entityName'] ?? ''}'.trim();
  if (entityName.isNotEmpty) {
    return entityName;
  }
  final supplierName = '${data['supplierName'] ?? ''}'.trim();
  if (supplierName.isNotEmpty) {
    return supplierName;
  }
  return 'unassigned';
}

String _recordEntityName(Map<String, dynamic> data, String key) {
  if (key == 'unassigned') {
    return 'Unassigned';
  }
  return '${data['entityName'] ?? data['supplierName'] ?? key}'.trim();
}

String _recordEntityType(Map<String, dynamic> data) {
  final type = '${data['entityType'] ?? ''}'.trim();
  return type.isEmpty ? 'vendor' : type;
}

DateTime? _parseDate(dynamic rawDate) {
  if (rawDate is DateTime) return rawDate;
  if (rawDate is String) return DateTime.tryParse(rawDate);
  if (rawDate is Timestamp) return rawDate.toDate();
  return null;
}
