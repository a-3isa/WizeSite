class WorkerProfile {
  const WorkerProfile({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.phoneNumber,
    required this.dailyWage,
    required this.workerType,
    required this.notes,
    required this.isArchived,
  });

  final String id;
  final String workspaceId;
  final String name;
  final String phoneNumber;
  final double dailyWage;
  final String workerType;
  final String notes;
  final bool isArchived;

  factory WorkerProfile.fromMap(String id, Map<String, dynamic> map) {
    return WorkerProfile(
      id: id,
      workspaceId: map['workspaceId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      dailyWage: (map['dailyWage'] as num?)?.toDouble() ?? 0,
      workerType: map['workerType'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      isArchived: map['isArchived'] as bool? ?? false,
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
    );
  }
}
