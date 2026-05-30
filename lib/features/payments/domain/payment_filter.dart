class PaymentFilter {
  const PaymentFilter({
    this.projectId,
    this.entityId,
    this.entityName,
    this.entityType,
    this.paymentMethod,
    this.paymentStatus,
    this.searchText,
    this.startDate,
    this.endDate,
  });

  final String? projectId;
  final String? entityId;
  final String? entityName;
  final String? entityType;
  final String? paymentMethod;
  final String? paymentStatus;
  final String? searchText;
  final DateTime? startDate;
  final DateTime? endDate;

  bool get hasActiveFilters => activeCount > 0;

  int get activeCount {
    return [
          projectId,
          entityId,
          entityName,
          entityType,
          paymentMethod,
          paymentStatus,
          searchText,
        ].where(_hasValue).length +
        (startDate != null || endDate != null ? 1 : 0);
  }

  PaymentFilter clear() => const PaymentFilter();

  PaymentFilter copyWith({
    String? projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return PaymentFilter(
      projectId: projectId ?? this.projectId,
      entityId: entityId ?? this.entityId,
      entityName: entityName ?? this.entityName,
      entityType: entityType ?? this.entityType,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      searchText: searchText ?? this.searchText,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }
}

bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;
