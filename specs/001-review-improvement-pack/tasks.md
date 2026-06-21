# Tasks: Buildozer Review Improvement Pack

**Input**: Design documents from `specs/001-review-improvement-pack/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/ui-behavior-contract.md`, `contracts/data-access-contract.md`, `quickstart.md`

**Tests**: Required by the constitution, specification acceptance scenarios, and quickstart. Within each story, write the listed tests first and confirm they fail for the intended missing behavior before production changes.

**Organization**: Tasks are grouped by user story so each story can be implemented and verified as an independent product increment. Existing branch work for payment navigation context, entity-summary access gating, scoped/paged custom-report export data, deterministic session restore, offline timestamp ordering, and the three root artifact deletions is baseline behavior to preserve with regression tests, not reimplement.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it changes different files and does not depend on an incomplete task.
- **[Story]**: Maps a task to User Story 1, 2, 3, or 4 from `spec.md`.
- Every task names the concrete file or files it changes.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add the dependencies, assets, and localization inventory needed by later story slices without changing behavior.

- [X] T001 Add `package_info_plus` and register `assets/branding/` in `pubspec.yaml`, then run `flutter pub get` and retain the resolved dependency changes in `pubspec.lock`
- [X] T002 Add an approved local Google sign-in logo at `assets/branding/google_g.png` and verify it is included by the asset declaration in `pubspec.yaml`
- [X] T003 [P] Extend localization coverage assertions for navigation, unread notifications, loading/recovery states, voice countdown/playback, filter removal, bulk archive, report scope/export, worker status, plan comparison, settings help/legal, and sync outcomes in `test/localization/localization_coverage_test.dart`
- [X] T004 Add the English and Arabic keys required by T003 in `lib/app/localization/app_localizations.dart` until the localization coverage test passes
- [X] T005 Record setup completion and any dependency/asset caveats in `specs/001-review-improvement-pack/quickstart.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish shared presentation and document-action primitives used across multiple user stories.

**CRITICAL**: Complete this phase before starting story implementation.

- [X] T006 [P] Write widget tests for loading skeletons, recoverable errors, empty CTAs, and semantic labels in `test/core/widgets/app_async_state_test.dart`
- [X] T007 Implement reusable `AppLoadingSkeleton`, `AppRecoverableError`, and `AppEmptyState` widgets in `lib/core/widgets/app_async_state.dart` until T006 passes
- [X] T008 [P] Write unit tests that map representative Firebase, storage, auth, recording, and unknown failures to localized message keys in `test/core/app_error_messages_test.dart`
- [X] T009 Implement exception-to-localization-key mapping without exposing raw exception text in `lib/core/utils/app_error_messages.dart` until T008 passes
- [X] T010 [P] Write tests for print and share/save document actions, including cancellation and failure results, in `test/features/reports/services/report_document_actions_test.dart`
- [X] T011 Implement the shared `Printing.layoutPdf` and `Printing.sharePdf` adapter in `lib/features/reports/services/report_document_actions.dart` until T010 passes
- [X] T012 Replace duplicated local section/loading/error/empty widgets with the shared primitives in `lib/features/reports/presentation/screens/reports_screen.dart`, `lib/features/settings/presentation/screens/settings_screen.dart`, and `lib/features/notifications/presentation/screens/notifications_screen.dart`
- [X] T013 Run `flutter test test/core/widgets/app_async_state_test.dart test/core/app_error_messages_test.dart test/features/reports/services/report_document_actions_test.dart` and record the foundational checkpoint in `specs/001-review-improvement-pack/quickstart.md`

**Checkpoint**: Shared assets, localization, async states, sanitized errors, and document actions are ready for all stories.

---

## Phase 3: User Story 1 - Reach Core Actions Faster (Priority: P1) MVP

**Goal**: Users can reach Home, Add, Reports, Projects, and Notifications directly, while the dashboard prioritizes action and presents coherent loading, refresh, error, summary, and upgrade states.

**Independent Test**: From a signed-in shell, navigate among all four branches, open Notifications with an unread badge, use every Add action, refresh the dashboard, and verify stable loading/recovery states without hidden destinations or duplicate launches.

### Tests for User Story 1

- [X] T014 [P] [US1] Write router and shell widget tests for four stable branches, active-branch reselection, Android back behavior, repeated taps, and no unreachable Add branch in `test/widget/app_bottom_nav_shell_test.dart`
- [X] T015 [P] [US1] Write Add hub action-parity and localized semantics tests for expense, payment, worker entry, and voice expense actions in `test/widget/add_hub_screen_test.dart`
- [X] T016 [P] [US1] Write notification provider/screen tests for bounded targeted reads, missing `readAt` as unread, badge count, mark-read behavior, loading, empty, and sanitized error states in `test/widget/notifications_screen_test.dart`
- [X] T017 [P] [US1] Add Firestore emulator rules tests proving only the target user can change only `readAt` in `functions/src/firestore_rules.test.ts`
- [X] T018 [P] [US1] Write dashboard provider and backend recomputation tests for one coherent `DashboardSnapshot`, one bounded `workspace_metrics` read, member/entry-only short-circuiting, current-week/top-value aggregation, bounded recent references, pending-queue deduplication, and friendly missing or restricted financial states in `test/features/dashboard/data/dashboard_providers_test.dart` and `functions/src/project_recompute_trigger.test.ts`
- [X] T019 [P] [US1] Write dashboard widget tests for quick-action ordering, pull-to-refresh, skeletons, retry, notification badge navigation, restricted-financial states for denied roles, profit/loss iconography, and upgrade placement in `test/widget/dashboard_screen_test.dart`

### Implementation for User Story 1

- [X] T020 [US1] Add Home, Add, Reports, and Projects as indexed shell branches and preserve route redirects in `lib/app/router.dart`
- [X] T021 [US1] Replace the two-tab/arc mapping with four persistent `NavigationDestination` items, localized semantics, stable branch indexes, and preserved offline-banner space in `lib/core/widgets/app_bottom_nav_shell.dart`
- [X] T022 [US1] Complete action parity in `lib/features/add/presentation/screens/add_hub_screen.dart`, remove obsolete commented action blocks, and prevent duplicate launches while prefetch is active
- [X] T023 [P] [US1] Add backward-compatible notification parsing and unread calculation in `lib/features/notifications/domain/notification_item.dart`
- [X] T024 [US1] Move the bounded targeted query and mark-read operation into `lib/features/notifications/data/notification_repository.dart` and expose Riverpod providers from `lib/features/notifications/data/notification_providers.dart`
- [X] T025 [US1] Update `lib/features/notifications/presentation/screens/notifications_screen.dart` to use typed items, mark displayed items read, and render shared loading/empty/recovery states
- [X] T026 [US1] Permit target-user updates of only `readAt` in `firestore.rules` and make T017 pass without broadening notification create/delete permissions
- [X] T027 [P] [US1] Add the immutable `DashboardSnapshot` and summary parsing/merge helpers in `lib/features/dashboard/domain/dashboard_snapshot.dart`
- [X] T028 [US1] Extend existing `workspace_metrics` recomputation with current-week/top/category/labor/equipment/payment data and 10 recent references in `functions/src/index.ts`, then replace duplicate raw weekly streams with one role-gated workspace-metrics plus offline-queue snapshot provider in `lib/features/dashboard/data/dashboard_providers.dart`
- [X] T029 [US1] Reorder `lib/features/dashboard/presentation/screens/dashboard_screen.dart` to sync status, quick actions, overview, weekly content, usage/upgrade; add notification badge, pull-to-refresh, shared placeholders, sanitized retry states, explanatory fallback labels, denied-role financial cards, and non-color profit/loss meaning
- [X] T030 [US1] Update prefetch targets for the four-branch shell and coherent dashboard snapshot in `lib/core/prefetch/app_prefetcher.dart` without weakening existing in-flight deduplication
- [X] T031 [US1] Run the US1 tests from T014-T019 plus `test/core/app_prefetcher_test.dart`, then record the US1 checkpoint in `specs/001-review-improvement-pack/quickstart.md`

**Checkpoint**: US1 is a deployable navigation/dashboard MVP with no inaccessible shell branch.

---

## Phase 4: User Story 2 - Capture and Manage Financial Activity Confidently (Priority: P2)

**Goal**: Voice, expense, and payment workflows provide visible progress, preserve context, support manageable filtering and safe bulk archive, and expose both print and share/save export paths.

**Independent Test**: Record and play a voice expense for longer than 20 seconds, apply/remove individual filters on a small screen, archive selected expenses/payments with confirmation and partial-failure recovery, export through print/share, and complete project-scoped payment navigation without losing context.

### Tests for User Story 2

- [X] T032 [P] [US2] Write state-machine tests for idle, recording, ready, playing, processing, failure, 60-second auto-stop, and user-currency fallback in `test/features/voice_expense/domain/voice_capture_state_test.dart`
- [X] T033 [P] [US2] Write voice screen tests for countdown, live audio feedback, production playback, rerecord/cancel, localized errors, and selected currency forwarding in `test/widget/voice_record_screen_test.dart`
- [X] T034 [P] [US2] Extend expense filter tests for one-token removal, distinct grouping controls, compact phone layout, and empty-list CTA in `test/widget/expenses_screen_filter_test.dart`
- [X] T035 [P] [US2] Extend payment list tests for one-token removal, compact phone layout, empty-list CTA, and grouping/filter distinction in `test/widget/paginated_lists_test.dart`
- [X] T036 [P] [US2] Write bulk archive tests for confirmation, cancellation, offline queue use, success, and partial failure in `test/widget/transaction_bulk_archive_test.dart`
- [X] T037 [P] [US2] Extend PDF action tests for expenses and payments to verify both print and share/save handoff in `test/features/reports/services/report_document_actions_test.dart`
- [X] T038 [P] [US2] Preserve project-scoped list-detail-edit-add return behavior with regression cases in `test/widget/payment_navigation_test.dart`

### Implementation for User Story 2

- [X] T039 [P] [US2] Add `VoiceCaptureStatus` and immutable timer/playback/error/currency state in `lib/features/voice_expense/domain/voice_capture_state.dart`
- [X] T040 [US2] Implement the 60-second timer, amplitude stream, playback lifecycle, cancellation, and sanitized failures in `lib/features/voice_expense/presentation/controllers/voice_capture_controller.dart`
- [X] T041 [US2] Refactor `lib/features/voice_expense/presentation/screens/voice_record_screen.dart` to render the controller state, enable waveform/countdown/playback for production, remove commented/debug-only UI, and forward the current user currency
- [X] T042 [P] [US2] Add reusable removable filter-token and grouped/filter control widgets in `lib/core/widgets/active_filter_bar.dart`
- [X] T043 [P] [US2] Add reusable selection state and confirmed per-record archive orchestration with partial-failure results in `lib/features/common/presentation/controllers/transaction_bulk_archive_controller.dart`
- [X] T044 [US2] Integrate removable filters, compact filter sections, empty CTA, selection mode, bulk archive, and print/share actions in `lib/features/expenses/presentation/screens/expenses_screen.dart`
- [X] T045 [US2] Integrate removable filters, compact filter sections, empty CTA, selection mode, bulk archive, and print/share actions in `lib/features/payments/presentation/screens/payments_screen.dart`
- [X] T046 [US2] Route expense/payment exports through `lib/features/reports/services/report_document_actions.dart` and keep existing `ReportPdfExporter` byte generation unchanged in `lib/features/reports/services/report_pdf_exporter.dart`
- [X] T047 [US2] Verify and preserve the existing optional `projectId` route propagation in `lib/core/constants/app_routes.dart`, `lib/app/router.dart`, `lib/features/payments/presentation/screens/payment_detail_screen.dart`, and `lib/features/payments/presentation/screens/add_payment_screen.dart`
- [X] T048 [US2] Run the US2 tests from T032-T038 plus `test/widget/prefill_and_sync_feedback_test.dart`, then record the US2 checkpoint in `specs/001-review-improvement-pack/quickstart.md`

**Checkpoint**: US2 is independently usable for voice capture and transaction management, including offline-safe bulk archive.

---

## Phase 5: User Story 3 - Understand Projects, Reports, and Operational Health (Priority: P3)

**Goal**: Project, report, worker, and resource views stay bounded, consistently scoped, financially understandable, and useful across active and historical work.

**Independent Test**: Browse and sort at least 50 projects, select an archived project and date range for reports, verify all charts/tables/exports share that scope, export more than 500 records, share one chart, and browse typed resources with worker status and accounting totals.

### Tests for User Story 3

- [X] T049 [P] [US3] Extend repository tests for a 50-item capped warm stream, stable recent/name paging, archived report selection, and globally ordered expense/income/net metric pages with stable cross-page tie-breakers in `test/features/projects/data/project_repository_test.dart`
- [X] T050 [P] [US3] Write project screen tests for status tabs, global sorting across multiple loaded pages, authorized financial metrics, denied-role recent/name-only fallback, non-color profit/loss meaning, pagination, and archive confirmation in `test/widget/projects_screen_test.dart`
- [X] T051 [P] [US3] Extend report request/provider tests for month-to-date default, one project/date scope across every provider, archived project paging, and denied-role short-circuiting in `test/features/reports/data/reports_providers_test.dart`
- [X] T052 [P] [US3] Extend report screen tests for export menu discoverability, date controls, loading progress/cancel, chart empty states, and historical project selection in `test/widget/reports_screen_test.dart`
- [X] T053 [P] [US3] Preserve project/date exclusion and multi-page export cases in `test/features/reports/services/report_export_data_builder_test.dart`
- [X] T054 [P] [US3] Write focused chart PDF/share tests for category, cashflow, and monthly-flow datasets in `test/features/reports/services/report_chart_exporter_test.dart`
- [X] T055 [P] [US3] Extend entity repository tests for post-backfill legacy visibility plus paged exact-type directories ordered by timestamp/name/ID in `test/features/entities/data/entity_repository_test.dart`
- [X] T056 [P] [US3] Write Add Hub/resource directory widget tests proving the visible Resources section reaches worker, contractor, equipment, and transport cross-project lists, including pagination, search, route handoff, denied financial totals, and non-worker accounting flows never exposing worker partial-payment controls in `test/widget/add_hub_screen_test.dart` and `test/widget/resource_directory_screen_test.dart`
- [X] T057 [P] [US3] Add worker model/repository/widget tests for active/inactive/terminated defaults, filters, edit persistence, and separate archive behavior in `test/features/workers/worker_status_test.dart`
- [X] T058 [P] [US3] Extend worker accounting tests for denied-role short-circuiting, exact maintained-summary totals beyond 50 records, paid/unpaid/partial calculation rules, `paidAmount` validation, confirmed totals, and unresolved legacy-partial explanations in `test/features/workers/worker_accounting_test.dart`
- [X] T059 [P] [US3] Add member/entry-only denial coverage for `workspace_metrics`, `project_metrics`, `worker_accounting_summaries`, and domain-accounting collections; add worker status and partial-payment validation cases; and keep entity backfill idempotency cases in `functions/src/firestore_rules.test.ts`, `functions/src/worker_mutation.test.ts`, and `functions/src/entity_last_used_backfill.test.ts`

### Implementation for User Story 3

- [X] T060 [US3] Cap `watchProjects` at 50 recent active projects; keep recent/name project queries independent of `project_metrics`; add paged status/archived inputs; and implement globally ordered expense/income/net paging from `project_metrics` with stable cursors and project hydration for accounting-authorized roles in `lib/features/projects/data/project_repository.dart`
- [X] T061 [US3] Add status tabs, role-gated sort control, paginated refresh, archive confirmation, and authorized-only expense/income/net metrics with trend icon/text plus denied-role fallback copy in `lib/features/projects/presentation/screens/projects_screen.dart`
- [X] T062 [P] [US3] Add immutable report scope state and month-to-date defaults around `ReportRequest` in `lib/features/reports/domain/report_scope.dart`
- [X] T063 [US3] Make all report metrics, categories, flow, workers, expenses, and payments providers consume the same project/date scope in `lib/features/reports/data/reports_providers.dart`
- [X] T064 [US3] Add paged active/archived project selector state for reports in `lib/features/reports/data/report_project_selector_provider.dart`
- [X] T065 [P] [US3] Implement single-chart PDF generation from chart data in `lib/features/reports/services/report_chart_exporter.dart`
- [X] T066 [US3] Refactor `lib/features/reports/presentation/screens/reports_screen.dart` to use one date scope, paged historical project selection, one export menu, progress/cancel feedback, shared empty states, and single-chart sharing
- [X] T067 [US3] Keep the existing scoped paged custom-export builder in `lib/features/reports/services/report_export_data_builder.dart` and add progress callbacks without reintroducing workspace-wide aggregation input
- [X] T068 [US3] Add an idempotent cursor-batched admin backfill command for missing entity `lastUsedAt` in `functions/src/entity_last_used_backfill.ts` and `functions/package.json`, and add timestamp/name/ID cursor-paged exact-type directory methods to `lib/features/entities/data/entity_repository.dart`
- [X] T069 [P] [US3] Add a reusable typed entity directory with search, pagination, access-gated totals, and accounting-route handoff in `lib/features/entities/presentation/screens/resource_directory_screen.dart`
- [X] T070 [US3] Replace project-only contractor/equipment/transport entry routes with top-level directory routes plus existing detail routes in `lib/core/constants/app_routes.dart` and `lib/app/router.dart`
- [X] T071 [US3] Wire worker, contractor, equipment, and transport directory entries into a visible Resources section in `lib/features/add/presentation/screens/add_hub_screen.dart` and configure typed directory screens in `lib/features/contractors/presentation/screens/contractors_screen.dart`, `lib/features/equipment/presentation/screens/equipment_screen.dart`, and `lib/features/transport/presentation/screens/transport_providers_screen.dart`
- [X] T072 [P] [US3] Add backward-compatible `status` parsing/serialization to `lib/features/workers/domain/worker_models.dart`
- [X] T073 [US3] Persist and filter worker status independently from archive in `lib/features/workers/data/worker_repository.dart` and `lib/features/workers/presentation/screens/add_worker_screen.dart`
- [X] T074 [US3] Add worker status filters/badges and shared loading/error/empty states in `lib/features/workers/presentation/screens/workers_screen.dart`
- [X] T075 [US3] Add a maintained `worker_accounting_summaries` consumer, isolate worker-only `paidAmount` editing behind `WorkerAccountingScreen`, and replace direct widget writes in `lib/features/common/presentation/screens/domain_accounting_records_screen.dart` with typed repository or mutation-adapter saves that show localized pending and recoverable failure states in `lib/features/workers/domain/worker_accounting_record.dart`, `lib/features/workers/presentation/screens/worker_accounting_screen.dart`, and `lib/features/common/presentation/screens/domain_accounting_records_screen.dart`
- [X] T076 [US3] Extend `functions/src/index.ts` and `firestore.rules` to maintain `worker_accounting_summaries`, gate `workspace_metrics`, `project_metrics`, and domain-accounting collection reads or writes to accounting-authorized roles, validate worker status and new worker-accounting partial `paidAmount` writes, and preserve old status defaults, readable legacy partial records, and independent `isArchived` behavior
- [X] T077 [US3] Add representative 50-project, 100-entity, 2,000-expense, 1,000-payment, and 500-plus export assertions covering global financial sort order, one-read dashboard composition, and post-backfill entity visibility in `test/features/performance/accounting_query_performance_test.dart`
- [X] T078 [US3] Run the US3 tests from T049-T059 and T077 plus `test/widget/entity_aggregation_screen_test.dart`, then record the US3 checkpoint in `specs/001-review-improvement-pack/quickstart.md`

**Checkpoint**: US3 is independently testable for bounded project/resource browsing and exact report scope.

---

## Phase 6: User Story 4 - Trust Account, Subscription, and Sync Feedback (Priority: P4)

**Goal**: Subscription, settings, login, connectivity, and sync recovery flows show truthful data, stable controls, actionable failures, and durable conflict outcomes.

**Independent Test**: Load live/empty subscription offers, update settings with simulated failures, sign in with stable local branding and inline validation, inspect/retry one failed sync item, and verify a skipped stale update explains that the newer version was retained.

### Tests for User Story 4

- [X] T079 [P] [US4] Replace fallback-price expectations with live-offer, unavailable/retry, recommendation, comparison, and trial metadata tests in `test/widget/plans_screen_test.dart`
- [X] T080 [P] [US4] Add purchase-adapter tests for nullable trial/package metadata and no fabricated packages in `test/subscription/revenuecat_purchase_coordinator_test.dart`
- [X] T081 [P] [US4] Extend settings tests for expanded currencies, rollback/error feedback, app version, help/legal links, and diagnostic confirmation in `test/widget/settings_screen_test.dart`
- [X] T082 [P] [US4] Extend login tests for local assets, password visibility, inline validation, stable Google slot, support-check failure, and restored-session routing in `test/widget/login_screen_test.dart`
- [X] T083 [P] [US4] Extend offline queue tests for individual retry and backward-compatible `applied`/`skippedNewerVersion` resolution serialization in `test/core/offline/offline_action_queue_test.dart`
- [X] T084 [P] [US4] Extend conflict tests so stale updates finish as synced with a durable newer-version-retained outcome in `test/core/offline/offline_conflict_resolution_test.dart`
- [X] T085 [P] [US4] Write sync-status widget tests for pending, failed, dead-letter, resolved items, individual retry, timestamps, and localized reasons in `test/widget/sync_status_screen_test.dart`
- [X] T086 [P] [US4] Extend cap-hit integration tests for clear limit copy and direct upgrade navigation in `test/integration/cap_hit_navigation_test.dart`

### Implementation for User Story 4

- [X] T087 [P] [US4] Extend `OfferingPackage` with nullable package/trial metadata, recommendation inputs, and feature keys in `lib/features/subscription/domain/purchase_coordinator.dart`
- [X] T088 [US4] Return only live RevenueCat packages and map store package/trial metadata in `lib/features/subscription/data/revenuecat_purchase_coordinator.dart`
- [X] T089 [US4] Replace hardcoded fallback prices with shared unavailable/retry state and add plan recommendation, feature comparison, savings/value, and actual trial copy in `lib/features/subscription/presentation/screens/plans_screen.dart`
- [X] T090 [US4] Clarify blocked quota and preserve direct paywall navigation in `lib/features/subscription/presentation/screens/limit_reached_screen.dart`
- [X] T091 [US4] Add optimistic-value rollback, localized setting errors, KWD/QAR/BHD/OMR/JOD options, app version, help/privacy/terms links, and diagnostic confirmation in `lib/features/settings/presentation/screens/settings_screen.dart`
- [X] T092 [US4] Use `assets/branding/app_icon.png` and `assets/branding/google_g.png`, add password reveal and inline field validation, and reserve stable Google-support-check space in `lib/features/auth/presentation/screens/login_screen.dart`
- [X] T093 [P] [US4] Extend `OfflineAction` with backward-compatible resolution fields and add a targeted retry operation in `lib/core/services/offline_action_queue.dart`
- [X] T094 [US4] Return applied/skipped-newer-version outcomes from queued mutation processing and persist them during drain in `lib/core/services/workspace_mutation_service.dart` and `lib/core/services/offline_queue_coordinator.dart`
- [X] T095 [P] [US4] Add sync-status providers that expose pending, failed, dead-letter, and recently resolved actions in `lib/core/providers/offline_queue_provider.dart`
- [X] T096 [US4] Add the localized sync-status list and individual retry controls in `lib/features/settings/presentation/screens/sync_status_screen.dart`
- [X] T097 [US4] Register the sync-status route and connect dashboard/shell sync cards to it in `lib/core/constants/app_routes.dart`, `lib/app/router.dart`, and `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
- [X] T098 [US4] Animate offline/reconnecting banner entry and exit without content jumps in `lib/core/widgets/app_bottom_nav_shell.dart`
- [X] T099 [US4] Run the US4 tests from T079-T086 plus `test/core/session_restore_service_test.dart`, then run `npm test` in `functions/` and record the US4 checkpoint in `specs/001-review-improvement-pack/quickstart.md`

**Checkpoint**: US4 is independently testable for truthful account/subscription state and recoverable sync behavior.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Close accessibility, localization, cleanup, performance, and release-verification work across all selected stories.

- [X] T100 [P] Remove obsolete commented UI and remaining duplicate private `_SectionHeader`, `_ErrorCard`, `_LoadingWidget`, and empty-state implementations from `lib/features/add/presentation/screens/add_hub_screen.dart`, `lib/features/voice_expense/presentation/screens/voice_record_screen.dart`, `lib/features/reports/presentation/screens/reports_screen.dart`, and `lib/features/settings/presentation/screens/settings_screen.dart`
- [X] T101 [P] Audit targeted screens including `lib/features/common/presentation/screens/domain_accounting_records_screen.dart` for hardcoded/debug-only production labels and raw exception rendering, then replace them through `lib/app/localization/app_localizations.dart` and `lib/core/utils/app_error_messages.dart`
- [X] T102 [P] Add RTL, semantics, and non-color status regression coverage for shell, quick actions, reports, and project cards in `test/widget/accessibility_rtl_test.dart`
- [X] T103 Add stable Arabic/English money and count formatting cases in `test/core/formatters_test.dart` and correct ambiguous output in `lib/core/utils/formatters.dart`
- [X] T104 Run `dart format --output=none --set-exit-if-changed lib test` and record formatting results in `specs/001-review-improvement-pack/quickstart.md`
- [X] T105 Run `flutter analyze` and record the final analyzer result in `specs/001-review-improvement-pack/quickstart.md`
- [X] T106 Run full `flutter test` and record the final test count and any PDF font warnings in `specs/001-review-improvement-pack/quickstart.md`
- [X] T107 Run `npm test` in `functions/`, execute Firestore emulator-backed rules tests when available, and record pass/skip details in `specs/001-review-improvement-pack/quickstart.md`
- [X] T108 Execute and record the release-candidate state audit, 100-run performance protocol, and available moderated usability cohorts from `specs/001-review-improvement-pack/quickstart.md`; record unexecuted cohort evidence as pending rather than passed and define the post-launch SC-006 comparison window
- [X] T109 Verify `firestore.indexes.json` matches only implemented project-metric/report/entity queries; run and record the entity `lastUsedAt` backfill plus worker-summary initialization before rollout; and document targeted deployment requirements for notification, metric-access, domain-accounting, worker-summary, and worker-validation changes in `specs/001-review-improvement-pack/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 Setup**: No dependencies; begin immediately.
- **Phase 2 Foundational**: Depends on Phase 1 and blocks all story phases.
- **US1 (P1 MVP)**: Depends on Phase 2.
- **US2 (P2)**: Depends on Phase 2; may run alongside US1 except for coordinated edits to localization, router, and shared report actions.
- **US3 (P3)**: Depends on Phase 2; may start independently, but route changes must be rebased after US1 shell changes and report-screen work must preserve the existing export-builder baseline.
- **US4 (P4)**: Depends on Phase 2; may run independently except for shell/dashboard route edits shared with US1.
- **Polish**: Depends on every story selected for delivery.

### User Story Dependencies

- **US1 Reach Core Actions Faster**: No story dependency; recommended MVP.
- **US2 Capture and Manage Financial Activity Confidently**: No functional dependency on US1; relies only on foundational widgets/actions and existing accounting repositories.
- **US3 Understand Projects, Reports, and Operational Health**: No functional dependency on US1/US2; must preserve existing report access and export correctness tests.
- **US4 Trust Account, Subscription, and Sync Feedback**: No functional dependency on other stories; sync-status navigation integration should be applied after any concurrent shell/dashboard changes.

### Within Each Story

- Write the story tests first and verify they fail for the intended missing behavior.
- Add domain/state types before repositories/providers/controllers.
- Add repositories/providers/controllers before screens and route integration.
- Apply Firestore rules/functions changes before relying on those contracts in production.
- Run the story checkpoint before marking the phase complete.

## Parallel Opportunities

- T002-T004 can run in parallel after T001 has established the dependency/asset declaration shape.
- T006, T008, and T010 are independent foundational test tasks.
- All test tasks at the start of each user story can run in parallel because they touch separate test files.
- US2, US3, and US4 can be developed in parallel after Phase 2 when shared-file ownership is coordinated.
- Domain/model tasks marked `[P]` can proceed alongside unrelated UI/service work in the same story.
- Final accessibility, cleanup, and formatter-test tasks T100-T103 can run in parallel before the final command gates.

## Parallel Example: User Story 1

```text
Task: T014 Write four-branch shell tests in test/widget/app_bottom_nav_shell_test.dart
Task: T016 Write notification read/badge tests in test/widget/notifications_screen_test.dart
Task: T017 Add notification read-state rules tests in functions/src/firestore_rules.test.ts
Task: T018 Write DashboardSnapshot provider and workspace-metrics recomputation tests
Task: T019 Write dashboard behavior tests in test/widget/dashboard_screen_test.dart
```

## Parallel Example: User Story 2

```text
Task: T032 Write voice state-machine tests in test/features/voice_expense/domain/voice_capture_state_test.dart
Task: T034 Extend expense filter tests in test/widget/expenses_screen_filter_test.dart
Task: T035 Extend payment list tests in test/widget/paginated_lists_test.dart
Task: T036 Write bulk archive tests in test/widget/transaction_bulk_archive_test.dart
Task: T038 Preserve payment navigation regressions in test/widget/payment_navigation_test.dart
```

## Parallel Example: User Story 3

```text
Task: T049 Extend project repository query tests in test/features/projects/data/project_repository_test.dart
Task: T051 Extend report scope provider tests in test/features/reports/data/reports_providers_test.dart
Task: T054 Write chart export tests in test/features/reports/services/report_chart_exporter_test.dart
Task: T056 Write Add Hub resource discoverability and directory tests
Task: T057 Add worker status tests in test/features/workers/worker_status_test.dart
```

## Parallel Example: User Story 4

```text
Task: T079 Replace fallback-price tests in test/widget/plans_screen_test.dart
Task: T081 Extend settings behavior tests in test/widget/settings_screen_test.dart
Task: T082 Extend login stability tests in test/widget/login_screen_test.dart
Task: T083 Extend offline action outcome tests in test/core/offline/offline_action_queue_test.dart
Task: T085 Write sync status tests in test/widget/sync_status_screen_test.dart
```

## Implementation Strategy

### MVP First

1. Complete Phase 1 and Phase 2.
2. Complete US1 through T031.
3. Stop and validate the four-branch shell, notifications, Add hub, and dashboard independently.
4. Demo or release the US1 increment before taking on the remaining review pack if schedule requires staged delivery.

### Incremental Delivery

1. **US1** resolves hidden navigation and dashboard clarity.
2. **US2** resolves core financial capture/list friction.
3. **US3** resolves project/report/resource visibility and scalability.
4. **US4** resolves pricing, settings, authentication, and sync trust.
5. **Polish** closes localization, accessibility, cleanup, and release evidence.

### Baseline Preservation

- Keep `test/widget/payment_navigation_test.dart`, `test/widget/entity_aggregation_screen_test.dart`, `test/features/reports/services/report_export_data_builder_test.dart`, `test/core/session_restore_service_test.dart`, and `test/core/offline/offline_action_queue_test.dart` passing throughout implementation.
- Do not restore the deleted root files `4.0.0`, `6.1.3`, or `_pickedFiles.removeAt(entry.key)`.
- Do not replace the existing scoped custom-report builder with workspace-wide aggregation.
- Do not broaden accounting access beyond owner, admin, and accounting-approved roles.

## Requirement Traceability

- **US1 tasks T014-T031**: FR-001 through FR-005A, FR-038 through FR-040, FR-044, FR-045, FR-050, FR-053, FR-056; SC-001, SC-004, SC-008, SC-009.
- **US2 tasks T032-T048**: FR-006 through FR-014, FR-043; SC-002, SC-004, SC-011, SC-014.
- **US3 tasks T049-T078**: FR-015 through FR-024, FR-041, FR-046, FR-047, FR-052; SC-003, SC-005, SC-007, SC-008, SC-012, SC-015.
- **US4 tasks T079-T099**: FR-025 through FR-037A, FR-048, FR-049, FR-051, FR-055; SC-004, SC-005, SC-010, SC-013, SC-016.
- **Setup/foundation/polish tasks T001-T013 and T100-T109**: FR-042 and FR-054 plus SC-004, SC-006, SC-008 cross-story localization, accessibility, cleanup, and verification obligations.

## Format Validation

- Every executable item uses `- [ ] T###` format.
- Every user-story task includes exactly one `[US1]`, `[US2]`, `[US3]`, or `[US4]` label.
- `[P]` appears only on tasks that can start independently in separate files.
- Every task names at least one concrete repository file path.
- Task IDs are sequential from T001 through T109.
