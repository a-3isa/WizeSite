enum ReportSection {
  expenses('expenses'),
  payments('payments'),
  weekly('weekly'),
  entities('entities'),
  daily('daily');

  const ReportSection(this.value);

  final String value;

  static ReportSection fromValue(Object? raw) {
    final value = '$raw';
    return ReportSection.values.firstWhere(
      (section) => section.value == value,
      orElse: () => ReportSection.expenses,
    );
  }
}

class ReportRequest {
  const ReportRequest({
    required this.projectId,
    required this.sections,
    this.startDate,
    this.endDate,
  });

  final String projectId;
  final Set<ReportSection> sections;
  final DateTime? startDate;
  final DateTime? endDate;

  bool get includeExpenses => sections.contains(ReportSection.expenses);
  bool get includePayments => sections.contains(ReportSection.payments);
  bool get includeWeekly => sections.contains(ReportSection.weekly);
  bool get includeEntities => sections.contains(ReportSection.entities);
  bool get includeDaily => sections.contains(ReportSection.daily);

  Map<String, dynamic> toMap() => {
    'projectId': projectId,
    'sections': sections.map((section) => section.value).toList(),
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
  };

  factory ReportRequest.fromMap(Map<String, dynamic> map) {
    final rawSections = map['sections'];
    final sections = rawSections is Iterable
        ? rawSections.map(ReportSection.fromValue).toSet()
        : <ReportSection>{ReportSection.expenses};
    return ReportRequest(
      projectId: '${map['projectId'] ?? ''}',
      sections: sections.isEmpty ? {ReportSection.expenses} : sections,
      startDate: _parseDate(map['startDate']),
      endDate: _parseDate(map['endDate']),
    );
  }
}

DateTime? _parseDate(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    return DateTime.tryParse(raw);
  }
  return null;
}
