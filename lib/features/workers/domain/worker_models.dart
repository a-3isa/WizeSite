import 'package:buildtrack_app/core/models/attachment.dart';

/// Lifecycle status of a worker, independent of the [WorkerProfile.isArchived]
/// record-visibility flag. Backward compatible: legacy records without a
/// `status` field are treated as [WorkerStatus.active].
enum WorkerStatus {
  active,
  inactive,
  terminated;

  /// Parses a stored value, falling back to [active] for null/unknown values.
  static WorkerStatus fromValue(String? value) {
    switch (value) {
      case 'inactive':
        return WorkerStatus.inactive;
      case 'terminated':
        return WorkerStatus.terminated;
      case 'active':
      default:
        return WorkerStatus.active;
    }
  }

  /// Stored representation.
  String get value => name;
}

class WorkerProfile {
  const WorkerProfile({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.phoneNumber,
    required this.dailyWage,
    required this.billingType,
    required this.workerType,
    required this.notes,
    required this.isArchived,
    this.status = WorkerStatus.active,
    this.clientMutationId = '',
  });

  final String id;
  final String workspaceId;
  final String name;
  final String phoneNumber;
  final double dailyWage;
  final String billingType;
  final String workerType;
  final String notes;
  final bool isArchived;

  /// Worker lifecycle status. Separate from [isArchived].
  final WorkerStatus status;
  final String clientMutationId;

  factory WorkerProfile.fromMap(String id, Map<String, dynamic> map) {
    return WorkerProfile(
      id: id,
      workspaceId: map['workspaceId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      dailyWage: (map['dailyWage'] as num?)?.toDouble() ?? 0,
      billingType: map['billingType'] as String? ?? 'daily',
      workerType: map['workerType'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      isArchived: map['isArchived'] as bool? ?? false,
      status: WorkerStatus.fromValue(map['status'] as String?),
      clientMutationId: map['clientMutationId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'workspaceId': workspaceId,
      'name': name,
      'phoneNumber': phoneNumber,
      'dailyWage': dailyWage,
      'billingType': billingType,
      'workerType': workerType,
      'notes': notes,
      'isArchived': isArchived,
      'status': status.value,
      if (clientMutationId.isNotEmpty) 'clientMutationId': clientMutationId,
    };
  }

  WorkerProfile copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? phoneNumber,
    double? dailyWage,
    String? billingType,
    String? workerType,
    String? notes,
    bool? isArchived,
    WorkerStatus? status,
    String? clientMutationId,
  }) {
    return WorkerProfile(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      dailyWage: dailyWage ?? this.dailyWage,
      billingType: billingType ?? this.billingType,
      workerType: workerType ?? this.workerType,
      notes: notes ?? this.notes,
      isArchived: isArchived ?? this.isArchived,
      status: status ?? this.status,
      clientMutationId: clientMutationId ?? this.clientMutationId,
    );
  }
}

class WorkerEntryRecord {
  const WorkerEntryRecord({
    required this.id,
    required this.workspaceId,
    required this.workerId,
    required this.projectId,
    required this.daysWorked,
    required this.dailyWage,
    required this.totalCost,
    required this.date,
    required this.notes,
    required this.isArchived,
    this.attachments = const [],
    this.clientMutationId = '',
  });

  final String id;
  final String workspaceId;
  final String workerId;
  final String projectId;
  final double daysWorked;
  final double dailyWage;
  final double totalCost;
  final DateTime date;
  final String notes;
  final bool isArchived;
  final List<Attachment> attachments;
  final String clientMutationId;

  factory WorkerEntryRecord.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) {
        return value;
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
        throw FormatException('Invalid worker entry date for $id: $value');
      }
      if (value != null) {
        try {
          final converted = (value as dynamic).toDate();
          if (converted is DateTime) {
            return converted;
          }
        } catch (_) {}
      }
      throw FormatException('Missing worker entry date for $id');
    }

    return WorkerEntryRecord(
      id: id,
      workspaceId: map['workspaceId'] as String? ?? '',
      workerId: map['workerId'] as String? ?? '',
      projectId: map['projectId'] as String? ?? '',
      daysWorked: (map['daysWorked'] as num?)?.toDouble() ?? 0,
      dailyWage: (map['dailyWage'] as num?)?.toDouble() ?? 0,
      totalCost: (map['totalCost'] as num?)?.toDouble() ?? 0,
      date: parseDate(map['date']),
      notes: map['notes'] as String? ?? '',
      isArchived: map['isArchived'] as bool? ?? false,
      attachments: Attachment.listFromDynamic(map['attachments']),
      clientMutationId: map['clientMutationId'] as String? ?? '',
    );
  }
}
