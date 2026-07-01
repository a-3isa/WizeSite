import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class PaymentRepository {
  Stream<List<PaymentRecord>> watchPayments(
    String workspaceId, {
    String? projectId,
  });
  Future<FirestorePage<PaymentRecord>> fetchPaymentsPage(
    String workspaceId, {
    String? projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  });
  Future<PaymentRecord?> getPayment(String paymentId);
  Future<MutationResult> createPayment({
    required String workspaceId,
    required String userId,
    required String projectId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? paymentStatus,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    double? projectTotalPaymentsBefore,
    List<Attachment>? attachments,
  });

  Future<void> updatePayment({
    required String paymentId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? paymentStatus,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    List<Attachment>? attachments,
  });

  Future<MutationResult> archivePayment(String paymentId);
}

class FirebasePaymentRepository implements PaymentRepository {
  FirebasePaymentRepository(
    this._firestore,
    this._mutationService,
    this._queue,
  );

  final FirebaseFirestore _firestore;
  final WorkspaceMutationService _mutationService;
  final OfflineActionQueue _queue;

  @override
  Stream<List<PaymentRecord>> watchPayments(
    String workspaceId, {
    String? projectId,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('payments')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false);
    if (projectId != null && projectId.isNotEmpty) {
      query = query.where('projectId', isEqualTo: projectId);
    }
    final baseStream = query
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => PaymentRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
    final queueStream = _queue.watch();
    return Stream.multi((controller) {
      List<PaymentRecord> current = const [];
      List<OfflineAction> actions = const [];

      void emit() {
        controller.add(
          _applyPendingPayments(
            baseItems: current,
            actions: actions,
            workspaceId: workspaceId,
            projectId: projectId,
            includePendingCreates: true,
          ),
        );
      }

      final baseSub = baseStream.listen((items) {
        current = items;
        emit();
      }, onError: controller.addError);
      final queueSub = queueStream.listen((value) {
        actions = value;
        emit();
      }, onError: controller.addError);
      controller.onCancel = () async {
        await baseSub.cancel();
        await queueSub.cancel();
      };
    });
  }

  @override
  Future<FirestorePage<PaymentRecord>> fetchPaymentsPage(
    String workspaceId, {
    String? projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('payments')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isArchived', isEqualTo: false);
    if (projectId != null && projectId.isNotEmpty) {
      query = query.where('projectId', isEqualTo: projectId);
    }
    if (entityId != null && entityId.isNotEmpty) {
      query = query.where('entityId', isEqualTo: entityId);
    } else if (entityName != null && entityName.trim().isNotEmpty) {
      query = query.where('entityName', isEqualTo: entityName.trim());
    }
    if (entityType != null && entityType.isNotEmpty) {
      query = query.where('entityType', isEqualTo: entityType);
    }
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      query = query.where('paymentMethod', isEqualTo: paymentMethod);
    }
    if (paymentStatus != null && paymentStatus.isNotEmpty) {
      query = query.where('paymentStatus', isEqualTo: paymentStatus);
    }
    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('date', isLessThanOrEqualTo: endDate);
    }
    query = query.orderBy('date', descending: true).limit(pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }

    final snap = await query.get();
    final items = snap.docs
        .map((doc) => PaymentRecord.fromMap(doc.id, doc.data()))
        .toList();
    final actions = await _queue.list();
    final mergedItems =
        _applyPendingPayments(
              baseItems: items,
              actions: actions,
              workspaceId: workspaceId,
              projectId: projectId,
              includePendingCreates: cursor == null,
            )
            .where(
              (payment) => _matchesPaymentFilters(
                payment,
                entityId: entityId,
                entityName: entityName,
                entityType: entityType,
                paymentMethod: paymentMethod,
                paymentStatus: paymentStatus,
                searchText: searchText,
                startDate: startDate,
                endDate: endDate,
              ),
            )
            .toList(growable: false);

    return FirestorePage<PaymentRecord>(
      items: mergedItems,
      hasMore: snap.docs.length == pageSize,
      nextCursor: snap.docs.isEmpty ? cursor : snap.docs.last,
    );
  }

  @override
  Future<PaymentRecord?> getPayment(String paymentId) async {
    final snap = await _firestore.collection('payments').doc(paymentId).get();
    if (!snap.exists) {
      return null;
    }
    return PaymentRecord.fromMap(snap.id, snap.data() ?? const {});
  }

  @override
  Future<MutationResult> createPayment({
    required String workspaceId,
    required String userId,
    required String projectId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? paymentStatus,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    double? projectTotalPaymentsBefore,
    List<Attachment>? attachments,
  }) async {
    final resolvedProjectTotalPaymentsBefore =
        await _projectPaymentBaseline(
          workspaceId: workspaceId,
          projectId: projectId,
        ) ??
        projectTotalPaymentsBefore;
    return _mutationService.createPayment(
      workspaceId: workspaceId,
      projectId: projectId,
      amount: amount,
      date: date,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      description: description,
      notes: notes,
      entityId: entityId,
      entityName: entityName,
      entityType: entityType,
      projectTotalPaymentsBefore: resolvedProjectTotalPaymentsBefore,
      attachments: attachments?.map((item) => item.toMap()).toList(),
    );
  }

  Future<double?> _projectPaymentBaseline({
    required String workspaceId,
    required String projectId,
  }) async {
    double? valueFrom(Map<String, dynamic>? data) {
      if (data == null) {
        return null;
      }
      final dataWorkspaceId = '${data['workspaceId'] ?? ''}'.trim();
      if (dataWorkspaceId.isNotEmpty && dataWorkspaceId != workspaceId) {
        return null;
      }
      return ((data['totalPayments'] as num?) ?? (data['totalIncome'] as num?))
          ?.toDouble();
    }

    try {
      final metricsSnap = await _firestore
          .collection('project_metrics')
          .doc(projectId)
          .get();
      final metricsValue = valueFrom(metricsSnap.data());
      if (metricsValue != null) {
        return metricsValue;
      }

      final projectSnap = await _firestore
          .collection('projects')
          .doc(projectId)
          .get();
      final projectValue = valueFrom(projectSnap.data());
      return projectValue;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> updatePayment({
    required String paymentId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? paymentStatus,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    List<Attachment>? attachments,
  }) async {
    final payment = await getPayment(paymentId);
    if (payment == null) {
      return;
    }
    await _mutationService.updatePayment(
      workspaceId: payment.workspaceId,
      paymentId: paymentId,
      projectId: payment.projectId,
      amount: amount,
      date: date,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      description: description,
      notes: notes,
      entityId: entityId,
      entityName: entityName,
      entityType: entityType,
      attachments:
          attachments?.map((item) => item.toMap()).toList() ??
          payment.attachments.map((item) => item.toMap()).toList(),
      previousAmount: payment.amount,
      previousDate: payment.date,
    );
  }

  @override
  Future<MutationResult> archivePayment(String paymentId) async {
    final payment = await getPayment(paymentId);
    if (payment == null) {
      return const MutationResult();
    }
    return _mutationService.archivePayment(
      workspaceId: payment.workspaceId,
      paymentId: paymentId,
      projectId: payment.projectId,
      amount: payment.amount,
      date: payment.date,
    );
  }

  List<PaymentRecord> _applyPendingPayments({
    required List<PaymentRecord> baseItems,
    required List<OfflineAction> actions,
    required String workspaceId,
    required String? projectId,
    required bool includePendingCreates,
  }) {
    final items = List<PaymentRecord>.from(baseItems);
    final archivedIds = <String>{};

    for (final action in actions) {
      final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
      if (payloadWorkspaceId != workspaceId) {
        continue;
      }
      if (action.type == OfflineActionTypes.archivePayment) {
        final paymentId = '${action.payload['paymentId'] ?? ''}';
        if (paymentId.isNotEmpty) {
          archivedIds.add(paymentId);
        }
      }
    }
    if (archivedIds.isNotEmpty) {
      items.removeWhere((item) => archivedIds.contains(item.id));
    }

    for (final action in actions) {
      if (action.type != OfflineActionTypes.updatePayment) {
        continue;
      }
      final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
      final payloadProjectId = '${action.payload['projectId'] ?? ''}';
      final paymentId = '${action.payload['paymentId'] ?? ''}';
      if (payloadWorkspaceId != workspaceId || paymentId.isEmpty) {
        continue;
      }
      if (projectId != null &&
          projectId.isNotEmpty &&
          payloadProjectId != projectId) {
        continue;
      }
      final index = items.indexWhere((item) => item.id == paymentId);
      if (index < 0) {
        continue;
      }
      final current = items[index];
      items[index] = PaymentRecord(
        id: current.id,
        workspaceId: current.workspaceId,
        projectId: current.projectId,
        amount:
            (action.payload['amount'] as num?)?.toDouble() ?? current.amount,
        date:
            DateTime.tryParse('${action.payload['date'] ?? ''}') ??
            current.date,
        paymentMethod:
            '${action.payload['paymentMethod'] ?? current.paymentMethod}',
        paymentStatus:
            '${action.payload['paymentStatus'] ?? current.paymentStatus}',
        description: '${action.payload['description'] ?? current.description}',
        notes: '${action.payload['notes'] ?? current.notes}',
        entityId:
            '${action.payload['entityId'] ?? current.entityId ?? ''}'.isNotEmpty
            ? '${action.payload['entityId'] ?? current.entityId ?? ''}'
            : null,
        entityName: '${action.payload['entityName'] ?? current.entityName}',
        entityType: '${action.payload['entityType'] ?? current.entityType}',
        attachments:
            (action.payload['attachments'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(Attachment.fromMap)
                .toList() ??
            current.attachments,
        isArchived: current.isArchived,
        clientMutationId: current.clientMutationId,
      );
    }

    if (includePendingCreates) {
      final liveMutationIds = items
          .map((item) => item.clientMutationId)
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final action in actions) {
        if (action.type != OfflineActionTypes.createPayment) {
          continue;
        }
        final clientMutationId = '${action.payload['clientMutationId'] ?? ''}';
        if (clientMutationId.isNotEmpty &&
            liveMutationIds.contains(clientMutationId)) {
          continue;
        }
        final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
        final payloadProjectId = '${action.payload['projectId'] ?? ''}';
        if (payloadWorkspaceId != workspaceId) {
          continue;
        }
        if (projectId != null &&
            projectId.isNotEmpty &&
            payloadProjectId != projectId) {
          continue;
        }
        items.insert(0, _paymentFromCreateAction(action));
      }
    }

    final deduped = <String, PaymentRecord>{};
    for (final item in items) {
      deduped[item.id] = item;
    }
    final result = deduped.values.toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  bool _matchesPaymentFilters(
    PaymentRecord payment, {
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (entityId != null &&
        entityId.isNotEmpty &&
        payment.entityId != entityId) {
      return false;
    }
    final normalizedEntityName = entityName?.trim().toLowerCase() ?? '';
    if ((entityId == null || entityId.isEmpty) &&
        normalizedEntityName.isNotEmpty &&
        payment.entityName.trim().toLowerCase() != normalizedEntityName) {
      return false;
    }
    if (entityType != null &&
        entityType.isNotEmpty &&
        payment.entityType != entityType) {
      return false;
    }
    if (paymentMethod != null &&
        paymentMethod.isNotEmpty &&
        payment.paymentMethod.toLowerCase() != paymentMethod.toLowerCase()) {
      return false;
    }
    if (paymentStatus != null &&
        paymentStatus.isNotEmpty &&
        payment.paymentStatus.toLowerCase() != paymentStatus.toLowerCase()) {
      return false;
    }
    final normalizedSearch = searchText?.trim().toLowerCase() ?? '';
    if (normalizedSearch.isNotEmpty &&
        !_containsAnyPaymentText(payment, normalizedSearch)) {
      return false;
    }
    if (startDate != null && payment.date.isBefore(startDate)) {
      return false;
    }
    if (endDate != null && payment.date.isAfter(endDate)) {
      return false;
    }
    return true;
  }

  bool _containsAnyPaymentText(PaymentRecord payment, String searchText) {
    return [
      payment.entityName,
      payment.description,
      payment.notes,
    ].any((value) => value.toLowerCase().contains(searchText));
  }

  PaymentRecord _paymentFromCreateAction(OfflineAction action) {
    final payload = action.payload;
    final parsedDate = DateTime.tryParse('${payload['date'] ?? ''}');
    return PaymentRecord(
      id: 'pending_${action.id}',
      workspaceId: '${payload['workspaceId'] ?? ''}',
      projectId: '${payload['projectId'] ?? ''}',
      amount: (payload['amount'] as num?)?.toDouble() ?? 0,
      date: parsedDate ?? action.createdAt,
      paymentMethod: '${payload['paymentMethod'] ?? 'cash'}',
      paymentStatus: '${payload['paymentStatus'] ?? 'paid'}',
      description: '${payload['description'] ?? payload['notes'] ?? ''}',
      notes: '${payload['notes'] ?? ''}',
      entityId:
          payload['entityId'] is String &&
              (payload['entityId'] as String).isNotEmpty
          ? payload['entityId'] as String
          : null,
      entityName: '${payload['entityName'] ?? ''}',
      entityType: '${payload['entityType'] ?? 'other'}',
      attachments:
          (payload['attachments'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Attachment.fromMap)
              .toList() ??
          const <Attachment>[],
      isArchived: false,
      clientMutationId: '${payload['clientMutationId'] ?? action.id}',
    );
  }
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return FirebasePaymentRepository(
    ref.watch(firestoreProvider),
    ref.watch(workspaceMutationServiceProvider),
    ref.watch(offlineActionQueueProvider),
  );
});
