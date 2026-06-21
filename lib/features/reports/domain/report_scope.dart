import 'package:buildtrack_app/features/reports/domain/report_request.dart';

const _unsetProjectId = Object();

class ReportScope {
  const ReportScope({
    required this.startDate,
    required this.endDate,
    this.projectId,
  });

  factory ReportScope.monthToDate({String? projectId, DateTime? now}) {
    final current = now ?? DateTime.now();
    return ReportScope(
      projectId: projectId,
      startDate: DateTime(current.year, current.month),
      endDate: DateTime(
        current.year,
        current.month,
        current.day,
        23,
        59,
        59,
        999,
      ),
    );
  }

  final String? projectId;
  final DateTime startDate;
  final DateTime endDate;

  bool get hasProject => projectId != null && projectId!.isNotEmpty;

  bool contains(DateTime value) =>
      !value.isBefore(startDate) && !value.isAfter(endDate);

  ReportScope copyWith({
    Object? projectId = _unsetProjectId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return ReportScope(
      projectId: identical(projectId, _unsetProjectId)
          ? this.projectId
          : projectId as String?,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  ReportRequest toRequest(Set<ReportSection> sections) {
    return ReportRequest(
      projectId: projectId ?? '',
      sections: sections,
      startDate: startDate,
      endDate: endDate,
    );
  }
}
