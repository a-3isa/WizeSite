class AccountingCategories {
  const AccountingCategories._();

  static const materials = 'materials';
  static const worker = 'worker';
  static const contractor = 'contractor';

  /// Deprecated: merged into [worker]. Retained only so historical records that
  /// still carry this value continue to parse and display. Not selectable.
  static const labor = 'labor';
  static const transport = 'transport';
  static const equipment = 'equipment';
  static const storage = 'storage';
  static const rentals = 'rentals';
  static const payments = 'payments';
  static const other = 'other';

  // Selectable categories. `labor` is intentionally excluded (deprecated,
  // merged into `worker`); it remains a constant for legacy record display.
  static const values = <String>[
    materials,
    worker,
    contractor,
    transport,
    equipment,
    storage,
    rentals,
    payments,
    other,
  ];
}
