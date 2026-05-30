# Tasks: Complete Accounting Scope

**Input**: Design documents from `specs/001-complete-accounting-scope/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/accounting-scope.openapi.yaml`, `quickstart.md`

**Tests**: Required by FR-029 and quickstart minimum automated test groups. Write test tasks before implementation tasks for each story and verify they fail before production changes.

**Organization**: Tasks are grouped by user story so each story can be implemented and tested independently after the foundational phase.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Restore a trustworthy baseline and prepare shared constants without changing feature behavior.

- [X] T001 Create the baseline results section for `flutter analyze`, `flutter test`, and `functions/npm test` in `specs/001-complete-accounting-scope/quickstart.md`
- [X] T002 Fix voice recording container regression in `lib/core/services/voice_recorder_service.dart`
- [X] T003 Fix FilePicker test harness initialization in `test/widget/add_entry_screen_test.dart`
- [X] T004 Fix AddExpense prefill recoverable error regression in `lib/features/expenses/presentation/screens/add_expense_screen.dart`
- [X] T005 [P] Add regression coverage for AddExpense prefill failure in `test/widget/prefill_and_sync_feedback_test.dart`
- [X] T006 [P] Add shared accounting category constants in `lib/core/constants/accounting_categories.dart`
- [X] T007 [P] Add shared payment status constants in `lib/core/constants/payment_statuses.dart`
- [X] T008 [P] Add shared accounting entity type constants in `lib/core/constants/accounting_entity_types.dart`
- [X] T009 Run setup-phase regression commands and update the setup checkpoint only in `specs/001-complete-accounting-scope/quickstart.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared models, services, permissions, offline primitives, indexes, and tests required before user stories.

**CRITICAL**: No user story work should begin until this phase is complete.

- [X] T010 [P] Extend attachment lifecycle fields and backward-compatible parsing in `lib/core/models/attachment.dart`
- [X] T011 [P] Add attachment lifecycle model tests in `test/core/models/attachment_test.dart`
- [X] T012 [P] Add accounting access role model in `lib/core/models/accounting_access_role.dart`
- [X] T013 [P] Add accounting access role tests in `test/core/models/accounting_access_role_test.dart`
- [X] T014 Implement role-check service for owner/admin/accounting-approved access in `lib/core/services/accounting_access_service.dart`
- [X] T015 Add role-check provider wrappers in `lib/core/providers/accounting_access_provider.dart`
- [X] T016 Add role restriction tests in `test/core/services/accounting_access_service_test.dart`
- [X] T017 Extend offline action payloads for attachment upload, entity upsert, summary delta, and clientSavedAt in `lib/core/services/offline_action_queue.dart`
- [X] T018 Add offline action serialization tests in `test/core/offline/offline_action_queue_test.dart`
- [X] T019 Implement pending attachment local-reference service in `lib/core/services/pending_attachment_service.dart`
- [X] T020 Add pending attachment service tests in `test/core/services/pending_attachment_service_test.dart`
- [X] T021 Extend storage upload service content types and retry-friendly errors in `lib/core/services/storage_upload_service.dart`
- [X] T022 Add storage upload validation and metadata tests in `test/core/services/storage_upload_service_test.dart`
- [X] T023 Add summary document contracts for project, weekly, category, and entity summaries in `lib/core/models/accounting_summary.dart`
- [X] T024 Add accounting summary model tests in `test/core/models/accounting_summary_test.dart`
- [X] T025 Update Firestore indexes for implemented entity, payment status, entity type, and summary query paths in `firestore.indexes.json`
- [X] T026 Update Firestore rules for role-restricted reports, balances, and attachments in `firestore.rules`
- [X] T027 Add Firestore rules tests for accounting role restrictions in `functions/src/firestore_rules.test.ts`
- [X] T028 Run foundational verification commands and update the foundational checkpoint only in `specs/001-complete-accounting-scope/quickstart.md`

**Checkpoint**: Foundation ready; user story implementation can begin in priority order or in parallel where capacity allows.

---

## Phase 3: User Story 1 - Capture Complete Accounting Transactions (Priority: P1) MVP

**Goal**: Users can create, edit, view, and save complete expense/payment records with structured accounting fields and attachments, including offline attachment references.

**Independent Test**: Create and edit an expense and payment with category, entity, purpose/description, amount, date, payment method, payment status, notes, and attachments; old records without new fields still load.

### Tests for User Story 1

- [X] T029 [P] [US1] Add expense model backward-compatibility and payment status tests in `test/features/expenses/domain/expense_test.dart`
- [X] T030 [P] [US1] Add payment model backward-compatibility and payment status tests in `test/features/payments/domain/payment_test.dart`
- [X] T031 [P] [US1] Add expense create/update structured field repository tests in `test/features/expenses/data/expense_repository_test.dart`
- [X] T032 [P] [US1] Add payment create/update structured field repository tests in `test/features/payments/data/payment_repository_test.dart`
- [X] T033 [P] [US1] Add offline attachment save tests for expense entry in `test/features/expenses/expense_attachment_workflow_test.dart`
- [X] T034 [P] [US1] Add offline attachment save tests for payment entry in `test/features/payments/payment_attachment_workflow_test.dart`
- [X] T035 [P] [US1] Add quick entry structured field validation tests in `test/widget/add_entry_screen_test.dart`

### Implementation for User Story 1

- [X] T036 [P] [US1] Extend Expense model fields and fallbacks in `lib/features/expenses/domain/expense.dart`
- [X] T037 [P] [US1] Extend Payment model fields and fallbacks in `lib/features/payments/domain/payment.dart`
- [X] T038 [US1] Persist expense purpose, description, payment status, entity type, and pending attachments in `lib/features/expenses/data/expense_repository.dart`
- [X] T039 [US1] Persist payment description, payment status, entity type, and pending attachments in `lib/features/payments/data/payment_repository.dart`
- [X] T040 [US1] Add payment status and purpose/description controls to full expense form in `lib/features/expenses/presentation/screens/add_expense_screen.dart`
- [X] T041 [US1] Add payment status and description controls to payment form in `lib/features/payments/presentation/screens/add_payment_screen.dart`
- [X] T042 [US1] Complete quick entry payment method, payment status, and repeated values in `lib/features/add/presentation/screens/add_entry_screen.dart`
- [X] T043 [US1] Integrate pending attachment save and retry state into expense save flow in `lib/core/services/expense_save_service.dart`
- [X] T044 [US1] Integrate pending attachment save and retry state into workspace mutation flow in `lib/core/services/workspace_mutation_service.dart`
- [X] T045 [US1] Add role-gated attachment preview/open/download denial, image preview, zoom, PDF open/download, and missing-file errors in `lib/core/widgets/attachment_tile.dart`
- [X] T046 [US1] Use shared attachment tile in expense detail screen in `lib/features/expenses/presentation/screens/expense_detail_screen.dart`
- [X] T047 [US1] Use shared attachment tile in payment detail screen in `lib/features/payments/presentation/screens/payment_detail_screen.dart`
- [X] T048 [US1] Update localized labels and errors for structured fields and pending attachments in `lib/app/localization/app_localizations.dart`

**Checkpoint**: US1 MVP is independently functional and regression-tested.

---

## Phase 4: User Story 2 - Find, Group, and Summarize Accounting Activity (Priority: P1)

**Goal**: Users can filter, search, group, collapse, and summarize expenses/payments with correct totals, pagination, and pending offline merges.

**Independent Test**: Combine filters and group modes on expenses/payments; verify active chips, no-results state, totals, counts, and quick summary cards.

### Tests for User Story 2

- [X] T049 [P] [US2] Add advanced expense filter repository tests in `test/features/expenses/data/expense_repository_test.dart`
- [X] T050 [P] [US2] Add advanced payment filter repository tests in `test/features/payments/data/payment_repository_test.dart`
- [X] T051 [P] [US2] Add expense grouping helper tests in `test/features/expenses/presentation/expense_grouping_test.dart`
- [X] T052 [P] [US2] Add collapsible expense group widget tests in `test/widget/expense_group_section_test.dart`
- [X] T053 [P] [US2] Add expense quick summary provider tests in `test/features/expenses/data/expense_summary_provider_test.dart`
- [X] T054 [P] [US2] Add screen-level filter chip and clear-all tests in `test/widget/expenses_screen_filter_test.dart`

### Implementation for User Story 2

- [X] T055 [P] [US2] Add expense filter model with entity type, payment status, search, and date range in `lib/features/expenses/domain/expense_filter.dart`
- [X] T056 [P] [US2] Add payment filter model with entity type, payment status, search, and date range in `lib/features/payments/domain/payment_filter.dart`
- [X] T057 [US2] Extend expense paged query filtering and pending-item matching in `lib/features/expenses/data/expense_repository.dart`
- [X] T058 [US2] Extend payment paged query filtering and pending-item matching in `lib/features/payments/data/payment_repository.dart`
- [X] T059 [P] [US2] Add reusable expense grouping helpers for list, exact date, relative date, category, entity, and payment method in `lib/features/expenses/presentation/models/expense_group.dart`
- [X] T060 [P] [US2] Add reusable collapsible expense group widget in `lib/features/expenses/presentation/widgets/expense_group_section.dart`
- [X] T061 [P] [US2] Add expense quick summary provider using scoped summaries and pending deltas in `lib/features/expenses/data/expense_summary_providers.dart`
- [X] T062 [US2] Complete expense filters, active chips, no-results state, row fields, grouping, and summary cards in `lib/features/expenses/presentation/screens/expenses_screen.dart`
- [X] T063 [US2] Complete payment filters, active chips, no-results state, and payment status support in `lib/features/payments/presentation/screens/payments_screen.dart`
- [X] T064 [US2] Add localized filter, group, no-results, and summary strings in `lib/app/localization/app_localizations.dart`

**Checkpoint**: US2 is independently functional and testable after US1/foundation.

---

## Phase 5: User Story 5 - Work Reliably Offline and at Scale (Priority: P1)

**Goal**: Users can work offline with transaction and attachment saves, last-saved-change-wins sync, summary-safe pending merges, and no unbounded normal-screen reads.

**Independent Test**: Queue expense/payment changes and attachments offline, verify pending display exactly once, reconnect, verify sync/upload, verify date-bounded weekly summaries and maintained aggregation reads.

### Tests for User Story 5

- [X] T065 [P] [US5] Add offline last-saved-change-wins conflict tests in `test/core/offline/offline_conflict_resolution_test.dart`
- [X] T066 [P] [US5] Add pending attachment retry tests in `test/core/services/pending_attachment_service_test.dart`
- [X] T067 [P] [US5] Add weekly dashboard date-bound and pending-dedup tests in `test/features/dashboard/data/dashboard_providers_test.dart`
- [X] T068 [P] [US5] Add entity summary scoped-read tests in `test/features/reports/data/entity_aggregation_providers_test.dart`
- [X] T069 [P] [US5] Add functions summary maintenance tests in `functions/src/project_recompute_trigger.test.ts`
- [X] T070 [P] [US5] Add representative dataset query-shape and performance tests in `test/features/performance/accounting_query_performance_test.dart`

### Implementation for User Story 5

- [X] T071 [US5] Implement last-saved-change-wins sync metadata in `lib/core/services/workspace_mutation_service.dart`
- [X] T072 [US5] Implement attachment upload retry orchestration after reconnect in `lib/core/services/offline_queue_coordinator.dart`
- [X] T073 [US5] Persist and clear pending attachment states during queue drain in `lib/core/services/pending_attachment_service.dart`
- [X] T074 [US5] Add maintained summary update handlers for expenses, payments, entities, weekly, and categories in `functions/src/index.ts`
- [X] T075 [US5] Replace weekly dashboard lower-bound-only reads with bounded or summary reads in `lib/features/dashboard/data/dashboard_providers.dart`
- [X] T076 [US5] Replace entity aggregation full collection streams with maintained summaries and scoped history reads in `lib/features/reports/data/entity_aggregation_providers.dart`
- [X] T077 [US5] Add dead-letter and retry feedback for failed attachment or sync actions in `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
- [X] T078 [US5] Update indexes for summary and bounded weekly query paths in `firestore.indexes.json`

**Checkpoint**: US5 is independently functional and testable for offline/performance correctness.

---

## Phase 6: User Story 3 - Reuse Entities and See Entity-Level Accountability (Priority: P2)

**Goal**: Users can reuse entities, avoid duplicates, add missing accounting entity domains, and review entity balances, history, attachments, and breakdowns.

**Independent Test**: Create/reuse entities from entry forms, verify recent-first suggestions and duplicate prevention, then open aggregation/detail for supplier, worker, contractor, transport, equipment, and other entities.

### Tests for User Story 3

- [X] T079 [P] [US3] Add entity normalized duplicate and recent-first tests in `test/features/entities/data/entity_repository_test.dart`
- [X] T080 [P] [US3] Add entity autocomplete widget tests in `test/widget/entity_autocomplete_field_test.dart`
- [X] T081 [P] [US3] Add entity attachment workflow and unauthorized preview/open/download tests in `test/features/entities/entity_attachment_workflow_test.dart`
- [X] T082 [P] [US3] Add worker accounting domain tests in `test/features/workers/worker_accounting_test.dart`
- [X] T083 [P] [US3] Add contractor accounting domain tests in `test/features/contractors/contractor_accounting_test.dart`
- [X] T084 [P] [US3] Add equipment accounting domain tests in `test/features/equipment/equipment_accounting_test.dart`
- [X] T085 [P] [US3] Add transport provider accounting domain tests in `test/features/transport/transport_provider_accounting_test.dart`
- [X] T086 [P] [US3] Add entity aggregation totals and breakdown tests in `test/features/reports/data/entity_aggregation_providers_test.dart`
- [X] T087 [P] [US3] Add entity aggregation screen search/type filter tests in `test/widget/entity_aggregation_screen_test.dart`

### Implementation for User Story 3

- [X] T088 [P] [US3] Complete entity model with type, normalizedName, attachments, and lastUsedAt in `lib/features/entities/domain/entity.dart`
- [X] T089 [US3] Fix entity repository normalized-name query, duplicate reuse, and recent-first ordering in `lib/features/entities/data/entity_repository.dart`
- [X] T090 [US3] Ensure typed entity creation/reuse from AddExpense without blocking transaction save in `lib/features/expenses/presentation/screens/add_expense_screen.dart`
- [X] T091 [US3] Ensure typed entity creation/reuse from AddPayment without blocking transaction save in `lib/features/payments/presentation/screens/add_payment_screen.dart`
- [X] T092 [US3] Ensure typed entity creation/reuse from quick entry without blocking transaction save in `lib/features/add/presentation/screens/add_entry_screen.dart`
- [X] T093 [P] [US3] Add entity attachment picker and validation UI in `lib/features/entities/presentation/screens/entity_detail_screen.dart`
- [X] T094 [P] [US3] Add worker accounting model with attachments in `lib/features/workers/domain/worker_accounting_record.dart`
- [X] T095 [P] [US3] Add contractor accounting model with attachments in `lib/features/contractors/domain/contractor_accounting_record.dart`
- [X] T096 [P] [US3] Add equipment accounting model with attachments in `lib/features/equipment/domain/equipment_accounting_record.dart`
- [X] T097 [P] [US3] Add transport provider accounting model with attachments in `lib/features/transport/domain/transport_provider_accounting_record.dart`
- [X] T098 [P] [US3] Add worker accounting repository/provider in `lib/features/workers/data/worker_accounting_repository.dart`
- [X] T099 [P] [US3] Add contractor accounting repository/provider in `lib/features/contractors/data/contractor_accounting_repository.dart`
- [X] T100 [P] [US3] Add equipment accounting repository/provider in `lib/features/equipment/data/equipment_accounting_repository.dart`
- [X] T101 [P] [US3] Add transport provider accounting repository/provider in `lib/features/transport/data/transport_provider_accounting_repository.dart`
- [ ] T102 [P] [US3] Add worker accounting list/detail/form UI with attachment count and open controls in `lib/features/workers/presentation/screens/worker_accounting_screen.dart`
- [ ] T103 [P] [US3] Add contractor accounting list/detail/form UI with attachment count and open controls in `lib/features/contractors/presentation/screens/contractors_screen.dart`
- [ ] T104 [P] [US3] Add equipment accounting list/detail/form UI with attachment count and open controls in `lib/features/equipment/presentation/screens/equipment_screen.dart`
- [ ] T105 [P] [US3] Add transport provider accounting list/detail/form UI with attachment count and open controls in `lib/features/transport/presentation/screens/transport_providers_screen.dart`
- [X] T106 [US3] Integrate worker, contractor, equipment, and transport records into entity aggregation summaries in `lib/features/reports/data/entity_aggregation_providers.dart`
- [ ] T107 [US3] Integrate worker, contractor, equipment, and transport records into report data providers in `lib/features/reports/data/reports_providers.dart`
- [ ] T108 [US3] Register worker accounting, contractor, equipment, and transport routes in `lib/app/router.dart`
- [ ] T109 [US3] Complete entity aggregation list, search, type filter, role gate, and empty/error states in `lib/features/reports/presentation/screens/entity_aggregation_screen.dart`
- [X] T110 [US3] Add entity aggregation detail view with history, category breakdown, payment method breakdown, and attachment count in `lib/features/reports/presentation/screens/entity_aggregation_detail_screen.dart`
- [ ] T111 [US3] Apply the shared role-gated attachment tile to entity and domain accounting screens in `lib/core/widgets/attachment_tile.dart`
- [ ] T112 [US3] Add localized domain accounting and attachment access-denied strings in `lib/app/localization/app_localizations.dart`

**Checkpoint**: US3 is independently functional and testable for reusable entities and aggregation.

---

## Phase 7: User Story 4 - Export Complete Accounting Reports (Priority: P2)

**Goal**: Authorized users can export every required report type with filters, totals, sections, empty-state handling, and recoverable PDF errors.

**Independent Test**: Generate populated and empty expenses, payments, entities, workers, contractors, daily, weekly, filtered, and combined reports; verify unauthorized users are denied.

### Tests for User Story 4

- [ ] T113 [P] [US4] Add report PDF exporter tests for expenses, payments, entities, workers, contractors, daily, weekly, filtered, combined, and empty data in `test/features/reports/services/report_pdf_exporter_test.dart`
- [ ] T114 [P] [US4] Add report provider date/filter data tests in `test/features/reports/data/reports_providers_test.dart`
- [ ] T115 [P] [US4] Add report screen export type and section selection widget tests in `test/widget/reports_screen_test.dart`
- [ ] T116 [P] [US4] Add unauthorized report export tests in `test/features/reports/data/report_access_test.dart`

### Implementation for User Story 4

- [ ] T117 [P] [US4] Split reusable PDF section builders into `lib/features/reports/services/report_pdf_sections.dart`
- [ ] T118 [US4] Add expenses-only, payments-only, entities, workers, contractors, daily, weekly, filtered, and combined builders in `lib/features/reports/services/report_pdf_exporter.dart`
- [ ] T119 [US4] Add report request model and selectable sections in `lib/features/reports/domain/report_request.dart`
- [ ] T120 [US4] Add bounded report data providers for each report type in `lib/features/reports/data/reports_providers.dart`
- [ ] T121 [US4] Add role gate and recoverable PDF error handling to reports screen in `lib/features/reports/presentation/screens/reports_screen.dart`
- [ ] T122 [US4] Add weekly export action from dashboard in `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
- [X] T123 [US4] Add entity summary export error handling in `lib/features/reports/presentation/screens/entity_aggregation_screen.dart`
- [ ] T124 [US4] Add localized report type, section, empty, and export error strings in `lib/app/localization/app_localizations.dart`

**Checkpoint**: US4 is independently functional and testable for report export behavior.

---

## Final Phase: Polish & Cross-Cutting Concerns

**Purpose**: End-to-end verification, documentation, accessibility, localization, and cleanup across all stories.

- [ ] T125 [P] Add accessibility labels for attachment, filter, group, summary, and export controls in `lib/app/localization/app_localizations.dart`
- [ ] T126 [P] Add manual QA result template for the full original scope in `specs/001-complete-accounting-scope/quickstart.md`
- [ ] T127 Run `flutter analyze` and record command output in `specs/001-complete-accounting-scope/quickstart.md`
- [ ] T128 Run full `flutter test` and record command output in `specs/001-complete-accounting-scope/quickstart.md`
- [ ] T129 Run targeted feature tests and record command output in `specs/001-complete-accounting-scope/quickstart.md`
- [ ] T130 Run functions `npm test` and record command output in `specs/001-complete-accounting-scope/quickstart.md`
- [ ] T131 Verify Firestore indexes and rules against actual implemented queries in `firestore.indexes.json`
- [ ] T132 Complete final production-readiness scope matrix in `specs/001-complete-accounting-scope/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 Setup**: No dependencies; begin immediately.
- **Phase 2 Foundational**: Depends on Phase 1; blocks all user stories.
- **US1 (P1 MVP)**: Depends on Phase 2.
- **US2 (P1)**: Depends on Phase 2 and benefits from US1 field/model completion.
- **US5 (P1)**: Depends on Phase 2 and should be completed before relying on summaries/offline behavior in US2/US3/US4 production rollout.
- **US3 (P2)**: Depends on Phase 2; integrates with US1 entity entry and US5 summaries.
- **US4 (P2)**: Depends on Phase 2; depends on US1 fields, US3 entity summaries, and US5 bounded report strategy for full coverage.
- **Final Phase**: Depends on all selected user story phases.

### User Story Dependencies

- **US1 Capture Complete Accounting Transactions**: MVP and first deliverable.
- **US2 Find, Group, and Summarize Accounting Activity**: Can begin after foundation; final accuracy depends on US1 fields and US5 summary rules.
- **US5 Work Reliably Offline and at Scale**: Can begin after foundation; should land before production reporting/aggregation rollout.
- **US3 Reuse Entities and See Entity-Level Accountability**: Can begin after foundation; integrates with US1 and US5.
- **US4 Export Complete Accounting Reports**: Can begin after foundation, but complete verification depends on US1, US3, and US5 data.

### Within Each User Story

- Tests first; verify failing tests before implementation.
- Models/constants before repositories/services.
- Repositories/services before screens/widgets.
- Providers before UI consumers.
- Cloud Functions/rules/index changes before relying on production query/security behavior.
- Story checkpoint verification before moving to the next priority.

## Parallel Execution Examples

### US1 Parallel Tasks

```text
Task: T029 Add expense model backward-compatibility and payment status tests in test/features/expenses/domain/expense_test.dart
Task: T030 Add payment model backward-compatibility and payment status tests in test/features/payments/domain/payment_test.dart
Task: T033 Add offline attachment save tests for expense entry in test/features/expenses/expense_attachment_workflow_test.dart
Task: T034 Add offline attachment save tests for payment entry in test/features/payments/payment_attachment_workflow_test.dart
```

### US2 Parallel Tasks

```text
Task: T049 Add advanced expense filter repository tests in test/features/expenses/data/expense_repository_test.dart
Task: T050 Add advanced payment filter repository tests in test/features/payments/data/payment_repository_test.dart
Task: T051 Add expense grouping helper tests in test/features/expenses/presentation/expense_grouping_test.dart
Task: T053 Add expense quick summary provider tests in test/features/expenses/data/expense_summary_provider_test.dart
```

### US5 Parallel Tasks

```text
Task: T065 Add offline last-saved-change-wins conflict tests in test/core/offline/offline_conflict_resolution_test.dart
Task: T067 Add weekly dashboard date-bound and pending-dedup tests in test/features/dashboard/data/dashboard_providers_test.dart
Task: T068 Add entity summary scoped-read tests in test/features/reports/data/entity_aggregation_providers_test.dart
Task: T069 Add functions summary maintenance tests in functions/src/project_recompute_trigger.test.ts
```

### US3 Parallel Tasks

```text
Task: T078 Add entity normalized duplicate and recent-first tests in test/features/entities/data/entity_repository_test.dart
Task: T079 Add entity autocomplete widget tests in test/widget/entity_autocomplete_field_test.dart
Task: T089 Add contractor accounting feature shell in lib/features/contractors/presentation/screens/contractors_screen.dart
Task: T090 Add equipment accounting feature shell in lib/features/equipment/presentation/screens/equipment_screen.dart
```

### US4 Parallel Tasks

```text
Task: T113 Add report PDF exporter tests in test/features/reports/services/report_pdf_exporter_test.dart
Task: T114 Add report provider date/filter data tests in test/features/reports/data/reports_providers_test.dart
Task: T115 Add report screen export type and section selection widget tests in test/widget/reports_screen_test.dart
Task: T116 Add unauthorized report export tests in test/features/reports/data/report_access_test.dart
```

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1 setup and fix the failing baseline tests.
2. Complete Phase 2 foundational primitives for attachments, roles, offline payloads, summaries, rules, and indexes.
3. Complete US1 transaction capture, edit, structured fields, and attachment workflow.
4. Stop and validate US1 independently with `flutter analyze`, targeted US1 tests, and relevant manual QA.

### Incremental Delivery

1. US1 delivers correct transaction capture.
2. US2 adds operational finding, grouping, and summaries.
3. US5 hardens offline and performance correctness.
4. US3 completes reusable entities and aggregation.
5. US4 completes exports.
6. Final phase closes verification, accessibility, localization, and readiness matrix.

### Parallel Team Strategy

After Phase 2, separate developers or agents can work on tests/helpers in different files. Avoid simultaneous edits to shared files such as `app_localizations.dart`, `expense_repository.dart`, `payment_repository.dart`, `dashboard_providers.dart`, and `report_pdf_exporter.dart` without coordination.

## Format Validation

- Every executable task uses `- [ ] T###` format.
- Every user story task includes `[US1]`, `[US2]`, `[US3]`, `[US4]`, or `[US5]`.
- Parallelizable tasks use `[P]` only when they touch separate files or can be safely started before dependent implementation.
- Every executable task names at least one concrete file path.
