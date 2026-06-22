# Quickstart: Buildozer Review Improvement Pack

This guide defines the verification path for the implementation tasks generated from this plan.

## 1. Verified Baseline

Run from `D:\WizeSite` unless noted otherwise.

| Check | Result on 2026-06-15 | Notes |
|-------|----------------------|-------|
| `flutter analyze` | PASS | No issues found |
| `flutter test` | PASS | 221 tests passed |
| `functions\npm test` | PASS with emulator caveat | 8 passed; 2 Firestore emulator-dependent suites skipped |

PDF tests emitted expected font-download fallback warnings in the offline test environment but still passed. Implementation must not convert those warnings into ignored Arabic rendering defects; device/manual export checks remain required.

## 2. Setup

```powershell
flutter pub get

Push-Location functions
npm ci
Pop-Location
```

After `package_info_plus` or asset declarations are added, rerun `flutter pub get` before targeted tests.

## 3. Required Implementation Order

1. Add shared loading/error/empty presentation primitives, localization keys, local sign-in assets, and package-info dependency.
2. Replace the shell mapping with Home and Projects branches plus the central Add popup, and add navigation/RTL/semantics tests before removing obsolete add/report shell destinations.
3. Add notification unread state, badge, rules tests, and dashboard navigation.
4. Extend the existing workspace metrics recomputation, role-gate restricted dashboard metrics, compose Home from one maintained workspace document plus local queue state, and add refresh or recovery states.
5. Complete voice capture timing, waveform, playback, currency, and localized failure handling.
6. Complete transaction filter tokens, compact filters, empty CTAs, bulk archive, and PDF sharing.
7. Complete bounded project browsing, globally ordered financial sorts from project metrics for accounting-authorized roles, denied-role project fallback states, status controls, card metrics, and archive confirmation.
8. Apply one report project/date scope to charts/tables/exports, add export menu/progress/chart sharing, and preserve paged custom export behavior.
9. Run the idempotent entity `lastUsedAt` backfill, initialize maintained worker accounting summaries, then enable typed cross-project resource directories, expose them from the Add destination, role-gate accounting details, and add worker status or explicit partial-payment summaries.
10. Remove fake subscription prices, enrich offer comparison/trial metadata, and finish settings/authentication improvements.
11. Add sync status, individual retry, persisted conflict outcome, and animated connectivity transitions.
12. Complete localization/accessibility cleanup, remove obsolete commented UI, and run all final gates.

## 4. Focused Automated Checks

### Navigation, Dashboard, and Notifications

```powershell
flutter test test/app/router_transition_test.dart
flutter test test/router/router_redirect_test.dart
flutter test test/features/dashboard/data/dashboard_providers_test.dart
flutter test test/widget/dashboard_screen_test.dart
flutter test test/widget/notifications_screen_test.dart
```

The last two files are planned additions.

### Voice and Transactions

```powershell
flutter test test/core/voice_recorder_service_test.dart
flutter test test/widget/voice_record_permission_test.dart
flutter test test/widget/voice_record_screen_test.dart
flutter test test/widget/expenses_screen_filter_test.dart
flutter test test/widget/paginated_lists_test.dart
flutter test test/widget/payment_navigation_test.dart
flutter test test/widget/transaction_bulk_archive_test.dart
```

### Projects, Reports, and Entities

```powershell
flutter test test/features/projects/data/project_repository_test.dart
flutter test test/widget/projects_screen_test.dart
flutter test test/widget/reports_screen_test.dart
flutter test test/features/reports/services/report_export_data_builder_test.dart
flutter test test/features/reports/services/report_pdf_exporter_test.dart
flutter test test/features/entities/data/entity_repository_test.dart
flutter test test/widget/app_bottom_nav_shell_test.dart
flutter test test/widget/dashboard_screen_test.dart
flutter test test/widget/resource_directory_screen_test.dart
flutter test test/features/workers/worker_accounting_test.dart
```

### Account, Subscription, and Sync

```powershell
flutter test test/widget/plans_screen_test.dart
flutter test test/widget/settings_screen_test.dart
flutter test test/widget/login_screen_test.dart
flutter test test/integration/cap_hit_navigation_test.dart
flutter test test/core/offline/offline_action_queue_test.dart
flutter test test/core/offline/offline_conflict_resolution_test.dart
flutter test test/core/services/offline_queue_coordinator_test.dart
flutter test test/widget/sync_status_screen_test.dart
```

### Backend and Rules

```powershell
Push-Location functions
npm test
Pop-Location
```

For rules tests, run with the Firestore emulator so skipped suites execute:

```powershell
firebase emulators:exec --only firestore "npm --prefix functions test"
```

## 5. Manual Device Checks

### Main experience

- Verify Home, Projects, the central Add popup, and project-scoped Reports on a narrow phone and a larger device.
- Verify Android back behavior and branch state restoration.
- Verify notification unread badge clears after viewing notifications and stays consistent after restart/sign-in on another device.
- Verify dashboard refresh, skeletons, sanitized errors, quick-action ordering, upgrade placement, and non-color profit/loss meaning.

### Voice and financial lists

- Record for more than 20 seconds and confirm automatic stop at 60 seconds.
- Verify live recording feedback, countdown, playback, rerecord, cancel, and processing in a release/profile build.
- Verify voice draft currency in EGP, USD, SAR, AED, KWD, QAR, BHD, OMR, and JOD settings.
- Verify expense/payment filters on the smallest supported phone height.
- Select multiple records, archive, cancel confirmation, and retry a partial failure while offline/online.
- Verify print and share/save for transaction PDFs.

### Projects and reports

- Browse at least 50 active projects and verify expense/income/net sorting remains globally correct while loading multiple pages.
- Confirm reports can select an archived project without loading all projects at once.
- Confirm one date range scopes every chart/table/export.
- Export a project/date range containing more than 500 expenses or payments.
- Share a single chart and confirm empty chart copy for no-data ranges.
- Confirm member/entry-only users never see report data or export actions.

### Resources, subscription, settings, and auth

- Open Home and verify its Resources section directly reaches workers, contractors, equipment, and transport directories.
- Sign in as member or entry-only and confirm dashboard financial cards, financial project sorts, project financial metrics, and worker accounting never render restricted financial data or trigger raw access failures.
- Run the entity backfill twice, verify the second run makes no changes, then confirm legacy entities missing `lastUsedAt` remain visible in deterministic directory order.
- Initialize worker summaries, then verify paid, unpaid, valid partial, and legacy unresolved partial worker records produce exact totals even when more than 50 records exist and show an incomplete-data explanation where required.
- Verify worker accounting entry saves show visible progress and localized recoverable failure messaging, and confirm contractor/equipment/transport accounting never shows worker-only partial-payment controls.
- Change worker status among active/inactive/terminated and confirm archive remains separate.
- Open plans with live packages, no packages, trial metadata, and purchase cancellation.
- Confirm app version/help/legal links and visible settings failure recovery.
- Confirm local app/Google assets, password reveal, inline validation, stable Google-button layout, and returning-session restore.

### Offline and accessibility

- Create two conflicting offline updates and confirm the sync screen explains that the newer saved version was retained.
- Retry one failed/dead-letter item without retrying unrelated items.
- Toggle connectivity and verify banner transitions do not abruptly shift content.
- Run English LTR and Arabic RTL checks with screen-reader semantics enabled.
- Confirm amounts remain understandable and all targeted strings are localized.

## 6. Performance Dataset

Use at least:

- 50 active projects plus archived projects.
- 100 entities across supported types.
- 2,000 expenses.
- 1,000 payments.
- One export scope containing more than 500 records.
- Pending, failed, dead-letter, applied, and skipped-newer-version queue items.

Run at least 100 timed project/report scope changes across representative narrow-phone and larger-device profiles. At least 95 must display updated content or explicit in-progress feedback within 3 seconds. Also verify dashboard refresh performs one maintained workspace-metrics read rather than a workspace-wide project-summary scan.

## 7. Success-Criteria Evidence Protocol

Record build identifier, date, device/profile, participant or run count, numerator, denominator, and result for every criterion. Do not mark unavailable evidence as passed.

- **Automated datasets**: SC-003 uses at least 20 project/date export combinations; SC-013 uses at least 20 seeded conflict cases.
- **Release-candidate state audit**: SC-004 audits every targeted loading/empty/offline/recoverable state; SC-008 audits every targeted financial screen in Arabic and English.
- **Timed datasets**: SC-007 uses at least 100 scope changes; SC-012 uses at least 100 project browse/filter/re-open cycles on the defined large dataset.
- **Moderated cohorts**: SC-001, SC-002, SC-005, SC-009, SC-010, SC-011, SC-014, SC-015, and SC-016 each use at least 20 eligible participants or returning sessions and the exact task wording from `spec.md`.
- **Post-launch metric**: SC-006 compares categorized support requests per 1,000 monthly active users for equal-length release cycles immediately before and after launch. During implementation, record the owner, category query, baseline window, and planned comparison date; leave the outcome pending until the post-launch window closes.

## 8. Final Quality Gate

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

Push-Location functions
npm test
Pop-Location
```

Document any skipped emulator, device, usability-cohort, or post-launch checks and the exact reason. Before directory rollout, execute the implemented entity backfill and worker-summary initialization and retain their scanned/updated counts. A targeted Firebase deploy is required when notification rules, metric-access rules, domain-accounting rules, workspace-metrics recomputation, worker-summary recomputation, or worker validation changes are included in the completed task set.

## 9. Implementation Progress Log

### Phase 1 — Setup (completed 2026-06-15)

- **T001**: Added `package_info_plus: ^8.0.0` to `pubspec.yaml` and registered the `assets/branding/` directory under `flutter.assets`. `flutter pub get` resolved successfully (`package_info_plus_platform_interface 3.2.1`). The pub registry reports 68 newer-but-incompatible package versions; none were upgraded to preserve the pinned `cloud_firestore` path override and existing constraints.
- **T002**: Added `assets/branding/google_g.png` (144×144, transparent) using Google brand colors, covered by the `assets/branding/` declaration. **Caveat**: this is a generated four-color "G" placeholder for offline/local sign-in rendering; replace it with the official mark from Google's "Sign in with Google" branding guidelines before release.
- **T003 / T004**: Extended `test/localization/localization_coverage_test.dart` with grouped assertions for navigation, unread notifications, loading/recovery states, voice countdown/playback, filter removal, bulk archive, report scope/export, worker status, plan comparison, settings help/legal, and sync outcomes; added the matching English + Arabic keys to `lib/app/localization/app_localizations.dart`. `flutter test test/localization/localization_coverage_test.dart` → **PASS (13 tests)**.


### Phase 2 — Foundational (completed 2026-06-15)

Shared presentation and document-action primitives, all test-first:

- **T006 / T007**: `lib/core/widgets/app_async_state.dart` adds `AppLoadingSkeleton` (animated skeleton bars + live-region semantics), `AppRecoverableError` (sanitized message, default localized heading, optional retry CTA), and `AppEmptyState` (icon + message + optional CTA). Tests: `test/core/widgets/app_async_state_test.dart` → **8 pass**.
- **T008 / T009**: `lib/core/utils/app_error_messages.dart` maps Firebase / storage / auth / recording / queued-callable / unknown failures to stable localized keys (`errorNetwork`, `errorPermissionDenied`, `errorUnauthenticated`, `errorNotFound`, `errorQuota`, `errorStorage`, `errorAuth`, `errorAuthInvalidCredentials`, `errorRecording`, `errorUnknown`) and never returns raw exception text. Keys added to EN + AR. Tests: `test/core/app_error_messages_test.dart` → **9 pass**.
- **T010 / T011**: `lib/features/reports/services/report_document_actions.dart` adds an injectable `ReportDocumentActions` adapter over `Printing.layoutPdf` / `Printing.sharePdf` returning `completed` / `dismissed` / `failed` results (PDF byte generation stays in `ReportPdfExporter`). Tests: `test/features/reports/services/report_document_actions_test.dart` → **6 pass**.
- **T012**: Replaced duplicated local loading/error/empty widgets with the shared primitives in `reports_screen.dart` (deleted `_LoadingWidget`/`_ErrorCard`/`_EmptyCard`; error states now route through `appErrorMessage`), `settings_screen.dart` (deleted `_ErrorCard`; sanitized subscription error), and `notifications_screen.dart` (empty/error/loading now use the shared widgets; previously rendered raw `error.toString()`). **Scope note**: local `_SectionHeader` consolidation and the bespoke `_SubscriptionLoadingCard` were intentionally left for the dedicated cleanup task **T100** to avoid visual regressions in this phase.

**Foundational checkpoint commands**

```powershell
flutter analyze lib   # touched files: No issues found
flutter test test/core/widgets/app_async_state_test.dart test/core/app_error_messages_test.dart test/features/reports/services/report_document_actions_test.dart
flutter test          # full suite: 255 passed (baseline 221 + 34 new foundational/localization tests), no regressions
```

PDF tests continue to emit the expected offline font-download fallback warnings (non-fatal). Phases 1 and 2 are complete and unblock all user-story phases (US1–US4).

### Phase 3 - User Story 1 (completed 2026-06-15)

- Replaced the unreachable three-branch/speed-dial shell with Home and Projects branches plus a central Add popup for Expense, Payment, and Voice Expense actions.
- Removed the standalone Add Hub route; Add actions now stay centralized in the bottom-shell popup and Resources live on Home.
- Added typed, bounded, target-user notification data with backward-compatible unread parsing, unread badge state, mark-read writes, shared loading/empty/recovery UI, and rules limiting targets to `readAt` updates only.
- Consolidated dashboard finance into one accounting-role-gated `workspace_metrics` snapshot plus pending queue overlay. Denied roles receive a friendly restricted state without starting financial reads. Backend recomputation now includes weekly totals, top category/entity, category/entity/payment summaries, labor/equipment totals, and at most 10 recent transactions.
- Reordered Home to sync feedback, quick actions, overview, usage, and upgrade; added pull-to-refresh, notification navigation, stable skeleton/retry states, sanitized errors, and explicit profit/loss icons.

```powershell
flutter analyze  # No issues found
flutter test test/widget/app_bottom_nav_shell_test.dart test/widget/notifications_screen_test.dart test/features/dashboard/data/dashboard_providers_test.dart test/widget/dashboard_screen_test.dart test/core/app_prefetcher_test.dart
Push-Location functions; npm test; Pop-Location  # 9 passed, 2 emulator-dependent suites skipped
```

Firestore notification and metric authorization tests compile and are present, but execution remains pending because `FIRESTORE_EMULATOR_HOST` is not configured in this environment.

### Phase 4 — User Story 2, voice-capture slice (completed 2026-06-15)

Test-first voice capture state machine (the list/filter/bulk-archive slice of US2, T034–T038 and T042–T047, is not yet done):

- **T039**: `lib/features/voice_expense/domain/voice_capture_state.dart` — `VoiceCaptureStatus` enum (idle/recording/ready/playing/processing/failure) + immutable `VoiceCaptureState` with elapsed/remaining countdown, normalized amplitude, sanitized `errorKey`, and resolved `currencyCode` (falls back to `EGP`).
- **T040**: `lib/features/voice_expense/presentation/controllers/voice_capture_controller.dart` — `StateNotifier` with a 60-second hard auto-stop, live amplitude subscription, playback lifecycle, cancellation, and sanitized failures via `appErrorMessageKey`. Depends on injectable `VoiceRecorderHandle` / `VoicePlaybackHandle` seams (real adapters wrap `VoiceRecorderService` + audioplayers). Added `amplitudeStream()` to `VoiceRecorderService` (normalized dBFS → 0–1). Tests: `test/features/voice_expense/domain/voice_capture_state_test.dart` → **13 pass** (uses `fakeAsync` for the 60s auto-stop).
- **T041**: `voice_record_screen.dart` refactored to render controller state — removed the large commented-out block and the `kDebugMode`-gated "Play Test" UI; playback is now production, the countdown shows remaining seconds, the waveform is amplitude-driven, and the user currency is forwarded to `VoiceProcessingScreen` (no more hardcoded `EGP`). Permission gating stays screen-level. Tests: `test/widget/voice_record_screen_test.dart` → **7 pass**. Updated `test/widget/voice_record_permission_test.dart` with a `currentUserSettingsProvider` override (the screen now resolves currency through the controller provider).

**Checkpoint commands**

```powershell
flutter analyze lib test   # No issues found
flutter test               # full suite: 286 passed, no regressions
```

### Phase 4 — User Story 2, lists & bulk-archive reusable primitives (completed 2026-06-15)

Self-contained, fully-tested building blocks for the expenses/payments list work. No edits to the core list screens yet (the screen integration T044/T045/T046, list-test extensions T034/T035, and payment-nav regression T038/T047 remain, so the US2 checkpoint T048 stays open).

- **T043 / T036**: `lib/features/common/presentation/controllers/transaction_bulk_archive_controller.dart` — reusable `TransactionBulkArchiveController` (`StateNotifier<BulkArchiveState>`) with selection (toggle/select/selectAll/clear) and a confirmed per-record `archiveSelected({archiveOne, confirm})` that reuses the existing archive mutations via an injected callback. Returns `BulkArchiveResult` (complete / partial-failure / total-failure / cancelled / queued); on partial failure only the failed ids stay selected for retry. Tests: `test/widget/transaction_bulk_archive_test.dart` → **7 pass**.
- **T042**: `lib/core/widgets/active_filter_bar.dart` — `ActiveFilter`, `FilterToken` (removable chip with localized `removeFilter` tooltip), and `ActiveFilterBar` (renders nothing when empty; clear-all only with >1 filter). Tests: `test/widget/active_filter_bar_test.dart` → **5 pass**.
- **T037**: extended `test/features/reports/services/report_document_actions_test.dart` with expense/payment print + share handoff coverage (the adapter the list screens will call). The actual screen routing (T046) lands with screen integration.

**Checkpoint commands**

```powershell
flutter analyze lib test   # No issues found
flutter test               # full suite: 300 passed, no regressions
```

### Phase 4 - User Story 2, transaction-management integration (completed 2026-06-15)

- Integrated removable filter tokens, compact filter/group controls, filtered and unfiltered empty-state actions, long-press selection, confirmed bulk archive, queued-write feedback, and partial-failure retry state into both expense and payment lists.
- Routed expense and payment PDF bytes through the shared print/share document-action adapter without changing PDF generation.
- Preserved optional `projectId` context through payment list, detail, edit, and add routes. Direct-entry back fallbacks now return to the project-scoped payments list.
- Added compact 390x844 widget coverage for token removal, grouping/filter separation, bulk archive, and the empty-list Add CTA. Added five payment navigation regressions covering list-to-detail, detail-to-edit, detail back, add back, and edit back.

```powershell
flutter analyze  # No issues found
flutter test test/features/voice_expense/domain/voice_capture_state_test.dart test/widget/voice_record_screen_test.dart test/widget/expenses_screen_filter_test.dart test/widget/paginated_lists_test.dart test/widget/transaction_bulk_archive_test.dart test/features/reports/services/report_document_actions_test.dart test/widget/payment_navigation_test.dart test/widget/prefill_and_sync_feedback_test.dart  # 46 passed
```

US2 is complete. The archive repository mutations continue to determine whether writes execute immediately or enter the existing offline queue; successful records are removed locally, and failed records remain selected for retry.

### Phase 5 - User Story 3, report foundations (in progress 2026-06-15)

- Added immutable report scope state with deterministic month-to-date defaults and a compatibility bridge for the existing project selection provider.
- Added paged active/archived report-project selector state backed by the existing bounded repository page methods.
- Preserved project/date exclusion and 500-plus row paging in custom exports, and added per-page progress callbacks plus a final completion event.
- Added category, cashflow, and monthly-flow single-chart PDF generation using the same Cairo font source as existing reports, with focused dataset tests.

```powershell
flutter test test/features/reports/data/reports_providers_test.dart test/features/reports/services/report_export_data_builder_test.dart test/features/reports/services/report_chart_exporter_test.dart  # 16 passed
flutter analyze  # No issues found
```

### Phase 5 - User Story 3, report interaction and export UX (completed 2026-06-15)

- Moved the report screen onto the shared project/date scope and exposed inclusive From/To controls using the month-to-date default.
- Replaced the warm active-only dropdown with the paged report selector, including an explicit archived-project mode and load-more state.
- Consolidated project, weekly, combined, entity, and custom actions into one discoverable export menu instead of a horizontally scrolling action row.
- Added live loaded-record progress for custom exports and cooperative cancellation checks between repository pages. User cancellation exits quietly without showing a failure notice.
- Added localized chart empty states and focused share-PDF actions for category, monthly-flow, and cashflow charts.

```powershell
flutter test test/features/reports/data/reports_providers_test.dart test/features/reports/services/report_export_data_builder_test.dart test/features/reports/services/report_chart_exporter_test.dart test/widget/reports_screen_test.dart test/localization/localization_coverage_test.dart --reporter compact  # 42 passed
flutter analyze  # No issues found
```

Chart PDF tests still emit the known offline Cairo download fallback warning; the tests pass with Helvetica fallback.

The chart PDF tests pass but emit the existing offline font-download fallback warning when `fonts.gstatic.com` is unavailable. Bundling a release font asset remains part of final release hardening if offline Arabic PDF generation must be guaranteed.

US3 remains open: project global sorting, full on-screen date-scope migration, historical selector UI, resource directories, worker accounting summaries, authorization rules, and performance fixtures are not yet claimed complete.

### Phase 5 - User Story 3, bounded project browsing (completed 2026-06-15)

- Capped the active project warm stream at 50 recent rows and moved recent/name browsing to stable project-field cursors independent of financial metric reads.
- Added status and archived paging plus globally ordered expense, income, and net pages sourced from maintained project metrics and hydrated in metric order.
- Added role-aware project controls: accounting roles can use financial sorts and see icon/text profit meaning; denied roles retain recent/name browsing without starting financial metric queries.
- Added paginated refresh, archive confirmation, and the composite Firestore indexes required by the new stable cursors.

```powershell
flutter test test/features/projects/data/project_repository_test.dart --reporter compact  # 10 passed
flutter test test/widget/projects_screen_test.dart test/localization/localization_coverage_test.dart --reporter compact  # 16 passed
Get-Content -Raw firestore.indexes.json | ConvertFrom-Json  # valid JSON
flutter analyze  # No issues found
```

The project browsing slice is complete. Deploy `firestore.indexes.json` before exercising these compound queries against a shared Firebase environment.

### Phase 5 - User Story 3, unified report data scope (completed 2026-06-15)

- Added one inclusive `ReportScope` input for the main report provider graph, retaining the deterministic month-to-date default and the temporary legacy project-selection bridge.
- Main-view expense and payment reads are project/date bounded and capped at 500 rows per type; returned rows are defensively filtered again before totals, category totals, monthly flow, and tables are derived.
- Worker, contractor, equipment, and transport report records now use the same project/date scope with a 50-row display bound. Top-worker values derive from the scoped worker rows rather than all-time project metrics.
- Accounting role resolution happens before project metrics, scoped repositories, or domain-accounting queries execute. Member and missing-access paths return no financial data.
- Added the required workspace/project/date indexes for the four domain-accounting collections. Custom report export remains the exhaustive path and continues paging in 500-row batches until exhaustion.

```powershell
flutter test test/features/reports/data/reports_providers_test.dart --reporter compact  # 13 passed
Get-Content -Raw firestore.indexes.json | ConvertFrom-Json  # valid JSON
flutter analyze  # No issues found
```

### Phase 5 — User Story 3, worker-status domain (completed 2026-06-15)

Foundational, collision-free domain slice (the worker-status repository wiring T073, screen filters/badges T074, and the broader T057 repo/widget tests remain):

- **T072**: `lib/features/workers/domain/worker_models.dart` — added the `WorkerStatus` enum (active/inactive/terminated) with null-safe `fromValue` (legacy records without `status` → `active`), a `status` field on `WorkerProfile` (defaulted, independent of `isArchived`), plus `toMap()` and `copyWith()` for serialization and edit persistence. Backward compatible — existing constructors keep working via the default.
- Model-level portion of **T057** covered by `test/features/workers/worker_status_test.dart` (defaults, parsing, unknown→active, archive-independence, toMap round-trip, copyWith) → **9 pass**. The repository/widget portions of T057 land with T073/T074.

**Checkpoint commands**

```powershell
flutter analyze lib test   # No issues found
flutter test               # full suite: 332 passed, no regressions
```

### Phase 5 — User Story 3, worker-status repository filtering (completed 2026-06-15)

Continues the worker-status slice with the collision-safe **filter** half of T073 (the **persist** half — threading `status` through `WorkspaceMutationService.create/updateWorker` and the Cloud Function — and the `add_worker_screen`/`workers_screen` UI (T073/T074) remain):

- `lib/features/workers/data/worker_repository.dart` — `watchWorkers` and `fetchWorkersPage` gained an optional `Set<WorkerStatus>? statuses` filter applied **independently of `isArchived`** (archived workers are always excluded; status filtering is layered on top). Default (`null`) preserves existing behavior — all non-archived workers, regardless of status. The offline update-merge now preserves a worker's existing `status`.
- Repository portion of **T057** added to `test/features/workers/worker_status_test.dart` (default returns all non-archived; single- and multi-status filters; terminated-but-unarchived stays visible) → **12 pass total** (8 model + 4 repository).
- **Test harness note**: `watchWorkers` combines a never-ending Hive `box.watch()` stream via `Stream.multi`, which is impractical to assert with `.first`; the filter is verified through `fetchWorkersPage` (a deterministic `Future`) using the identical predicate. Hive is initialized once per group (`setUpAll`) with unique per-test box names to avoid re-init deadlocks.

**Checkpoint commands**

```powershell
flutter analyze lib test   # No issues found
flutter test               # full suite: 336 passed, no regressions
```

### Phase 5 - User Story 3, entity directory paging and backfill (completed 2026-06-15)

- Added exact-type cursor-paged entity directory reads ordered by `lastUsedAt desc`, `normalizedName asc`, and stable `id asc`, plus name and ID directory sorts.
- New entity records now persist their document ID into the `id` field so directory cursors do not depend on client-only document-name behavior.
- Added an idempotent admin backfill command for legacy entities missing `lastUsedAt`; fallback order is `createdAt`, then `updatedAt`, then Unix epoch, while also repairing missing `id` and `normalizedName`.
- Added matching composite indexes for exact-type entity directories.

Backfill command before rollout:

```powershell
Push-Location functions
$env:ENTITY_BACKFILL_BATCH_SIZE='200'
npm run backfill:entity-last-used
Pop-Location
```

Checkpoint commands:

```powershell
flutter test test/features/entities/data/entity_repository_test.dart test/widget/entity_autocomplete_field_test.dart --reporter compact  # 8 passed
Push-Location functions; npm test -- --test-name-pattern "entity lastUsedAt"; Pop-Location  # 11 passed, 2 emulator-dependent suites skipped
Get-Content -Raw firestore.indexes.json | ConvertFrom-Json  # valid JSON
flutter analyze  # No issues found
```

### Phase 6 — User Story 4, OfferingPackage metadata (completed 2026-06-16)

Clean US4 domain foundation (US4 was untouched; chosen to avoid the active US3 collision):

- **T087**: `lib/features/subscription/domain/purchase_coordinator.dart` — extended `OfferingPackage` with nullable trial/package metadata (`packageType`, `trialPeriodLabel`, `hasFreeTrial`), recommendation input (`isRecommended`), local feature-comparison `featureKeys`, and `savingsLabel`, plus `copyWith`. All new fields are nullable/defaulted, so the RevenueCat adapter and plans screen keep compiling. Tests: `test/subscription/offering_package_test.dart` → **3 pass**.
- This is the view-model the live-offer adapter (T088) and plans screen (T089) build on; those remain.

**Checkpoint commands**

```powershell
flutter analyze lib test   # No issues found
flutter test               # full suite: 351 passed, no regressions
```

### Phase 5 — User Story 3, worker-accounting partial-payment domain (completed 2026-06-16)

The keystone for the remaining US3 worker-accounting work (T058/T075/T076). Pure, fully-tested domain — the maintained-summary recompute (functions T076), access gating + paidAmount validation rules (T076/T059), the summary consumer + domain-accounting typed writes (T075), and the performance assertions (T077) still remain:

- `lib/features/workers/domain/worker_accounting_record.dart` — added nullable `paidAmount`; deterministic derivation (`confirmedPaidAmount`, `outstandingAmount`, `isLegacyPartialUnresolved`): paid→full, unpaid→0, partial-with-amount→that amount, partial-without→**unresolved** (null, excluded from confirmed totals); `validatePaidAmount` (required/too-low/too-high localization keys); and `WorkerAccountingTotals.fromRecords` (confirmed paid/outstanding, full total, unresolved-legacy count). Backward compatible (`paidAmount` nullable; legacy partials disclosed, never estimated).
- Localization: added `workerPaidAmount*`, `workerLegacyPartialUnresolved`, `workerConfirmed*` keys (EN + AR).
- Domain portion of **T058** in `test/features/workers/worker_accounting_test.dart` → **25 pass** (was 2).

**Checkpoint commands**

```powershell
flutter analyze lib test   # No issues found
flutter test               # full suite: 361 passed, no regressions
```

### Phase 5 — US3 worker-accounting maintained-summary consumer (completed 2026-06-16)

Verified pure-Dart read-side of T075 (the backend recompute that *writes* this summary is the deferred T076 emulator work):

- `lib/features/workers/domain/worker_accounting_record.dart` — added `WorkerAccountingSummary` (maintained exact aggregate: totalAmount, confirmedPaid, confirmedOutstanding, unresolvedLegacyCount, recordCount + `hasUnresolvedLegacy`).
- `lib/features/workers/data/worker_accounting_repository.dart` — `fetchSummary({workspaceId, workerId})` reads `worker_accounting_summaries/{workspaceId}_{workerId}` (returns null when not yet computed). This defines the read contract the deferred functions will satisfy, and gives **exact totals independent of the 50-record `fetchForWorker` page cap**.
- T058 summary portion in `test/features/workers/worker_accounting_test.dart` → **15 pass** (exact totals over 120 records, null when absent, fromMap).

**Checkpoint commands**

```powershell
flutter analyze lib test   # No issues found
flutter test               # full suite: 364 passed, no regressions
```

**Remaining US3 (deferred):** T076 functions + firestore.rules and T059 emulator rules tests (focused backend session); T075 UI (isolate paid-amount editing to WorkerAccountingScreen, replace direct writes in domain_accounting_records_screen with typed saves); T077 performance assertions; T078 checkpoint.

### Phase 5 - User Story 3, worker-accounting backend/UI/performance closure (completed 2026-06-16)

Closed the remaining US3 worker-accounting and performance tasks:

- `DomainAccountingRecordsScreen` now role-gates before reads/actions, uses shared loading/empty/recoverable-error states, and delegates writes through typed save adapters instead of embedding direct Firestore mutations in the widget.
- `WorkerAccountingScreen` owns worker-only partial-payment editing, validates `paidAmount`, and displays the maintained `worker_accounting_summaries` exact totals so totals are not limited by the visible 50-record page.
- `functions/src/index.ts` maintains `worker_accounting_summaries` from `worker_accounting_records`, preserves legacy status defaults through `normalizeWorkerStatus`, and rejects invalid worker statuses.
- `firestore.rules` gates `workspace_metrics`, `project_metrics`, domain-accounting records, worker-accounting records, and worker-accounting summaries to accounting-authorized roles; new worker partial records must include a valid `paidAmount`, while legacy partial records remain readable.
- `test/features/performance/accounting_query_performance_test.dart` now pins the 50-project global financial sort path, one-doc dashboard metrics composition, post-backfill entity visibility, and 500-plus export paging loops.

Checkpoint commands:

```powershell
flutter test test/features/workers/worker_accounting_test.dart test/widget/worker_accounting_screen_test.dart --reporter compact  # 19 passed
firebase emulators:exec --only firestore "npm --prefix functions test"  # 59 passed, 0 skipped
flutter test test/features/projects/data/project_repository_test.dart test/widget/projects_screen_test.dart test/features/reports/data/reports_providers_test.dart test/widget/reports_screen_test.dart test/features/reports/services/report_export_data_builder_test.dart test/features/reports/services/report_chart_exporter_test.dart test/features/entities/data/entity_repository_test.dart test/widget/app_bottom_nav_shell_test.dart test/widget/dashboard_screen_test.dart test/widget/resource_directory_screen_test.dart test/features/workers/worker_status_test.dart test/features/workers/worker_accounting_test.dart test/widget/worker_accounting_screen_test.dart test/features/performance/accounting_query_performance_test.dart test/widget/entity_aggregation_screen_test.dart --reporter compact
flutter analyze  # No issues found
```

**US3 status:** T049-T078 complete and independently verified.

### Phase 6 - User Story 4, account/subscription/sync trust closure (completed 2026-06-16)

Closed the remaining US4 account, subscription, settings, login, and sync-recovery tasks:

- Subscription plans now render only live RevenueCat offers, preserve nullable store metadata, show plan recommendation/comparison details, and use an honest retryable unavailable state instead of fabricated fallback prices.
- Limit-reached states explain the exact blocked quota when current/max values are available and preserve the direct upgrade path.
- Settings now includes expanded currencies, optimistic rollback with localized failure feedback, app version, help/legal links, Sync status navigation, and confirmation before diagnostic/crash actions.
- Login now uses local branding assets, inline field validation, password reveal, a stable Google sign-in slot, support-check failure fallback, and restored-session routing.
- Offline queue actions now serialize `applied` and `skippedNewerVersion` resolution metadata, support individual retry reset, and mark stale last-saved conflicts as synced with a visible newer-version-kept outcome.
- Sync status now lists pending, failed, dead-letter, and recently resolved queue items with timestamps, localized resolution reasons, and individual retry controls. Dashboard sync cards and Settings navigation open the status route.
- The offline banner now renders as an animated overlay so shell content geometry does not jump when connectivity changes.

Checkpoint commands:

```powershell
flutter test test/subscription/revenuecat_purchase_coordinator_test.dart test/widget/plans_screen_test.dart test/widget/settings_screen_test.dart test/widget/login_screen_test.dart test/core/offline/offline_action_queue_test.dart test/core/offline/offline_conflict_resolution_test.dart test/widget/sync_status_screen_test.dart test/integration/cap_hit_navigation_test.dart test/core/session_restore_service_test.dart --reporter compact  # 36 passed
Push-Location functions; npm test; Pop-Location  # 14 passed, 2 emulator-dependent tests skipped because FIRESTORE_EMULATOR_HOST was not set
flutter analyze  # No issues found
```

**US4 status:** T079-T099 complete and independently verified.

### Phase 7 - Polish, accessibility, localization, and final local gates (completed 2026-06-16)

Closed the cross-cutting cleanup and verification tasks that can be completed safely in the local workspace:

- **T100/T101 cleanup audit**: Removed the obsolete Add Hub surface, kept Add actions in the central bottom-shell popup, replaced remaining duplicate private `_SectionHeader` widgets in Reports and Settings with the shared `SectionHeader`, removed the stale reports cleanup comment, localized the debug-only Crashlytics diagnostics labels, and confirmed targeted screens no longer expose raw `error.toString()` rendering in the audited paths. `DomainAccountingRecordsScreen` continues to use `appErrorMessage`.
- **T102 accessibility/RTL coverage**: Added `test/widget/accessibility_rtl_test.dart` covering Arabic RTL shell destinations, quick-action button semantics, Reports export discoverability, and project-card status/profit cues that do not rely on color alone.
- **T103 formatter correctness**: Added stable English/Arabic money and count assertions in `test/core/formatters_test.dart`; added `Formatters.count`; made Arabic money/count output deterministic with Arabic-Indic digits plus Arabic thousands/decimal separators; fixed worker accounting summaries to pass the active UI locale instead of relying on formatter defaults.

Checkpoint commands:

```powershell
flutter test test/localization/localization_coverage_test.dart test/widget/settings_screen_test.dart test/widget/app_bottom_nav_shell_test.dart test/widget/dashboard_screen_test.dart test/widget/reports_screen_test.dart --reporter compact
flutter test test/widget/accessibility_rtl_test.dart --reporter compact  # 4 passed
flutter test test/core/formatters_test.dart --reporter compact  # 5 passed
flutter test test/widget/worker_accounting_screen_test.dart --plain-name "owner sees maintained full-ledger worker summary" --reporter compact  # 1 passed
```

Final local quality gate:

```powershell
dart format --output=none --set-exit-if-changed lib test  # Formatted 276 files (0 changed)
flutter analyze  # No issues found
flutter test --reporter compact  # 398 passed
Push-Location functions; npm test; Pop-Location  # 14 passed, 2 emulator-dependent suites skipped because FIRESTORE_EMULATOR_HOST was not set
Get-Content -Raw firestore.indexes.json | ConvertFrom-Json  # valid JSON
```

Function test caveat: `functions/src/firestore_rules.test.ts` and emulator-backed portions of `functions/src/project_recompute_trigger.test.ts` were skipped in the local `npm test` run because no Firestore emulator target was configured. The earlier US3 emulator run remains documented above, but release candidates should rerun:

```powershell
firebase emulators:exec --only firestore "npm --prefix functions test"
```

`firestore.indexes.json` validation on 2026-06-16 parsed successfully. Implemented query groups present include project metrics (`project_metrics` financial sorts), report/export inputs (`expenses`, `payments`, domain accounting records, summary collections), entity directories (`entities`), notifications, projects, workers, worker entries, and memberships. No new index edits were made during the polish pass.

Release-candidate evidence status:

- **State audit**: Automated coverage now exercises shell, quick actions, reports, project cards, settings, sync status, denied financial states, loading/empty/recoverable states, and sanitized errors. Manual device audit from sections 5-7 remains required before release sign-off.
- **100-run performance protocol**: Pending execution on the defined large dataset and representative devices. Required result remains at least 95 of 100 project/report scope changes showing content or explicit progress within 3 seconds.
- **Moderated usability cohorts**: Pending. SC-001, SC-002, SC-005, SC-009, SC-010, SC-011, SC-014, SC-015, and SC-016 must each use at least 20 eligible participants or returning sessions; unavailable cohort evidence is not marked passed.
- **SC-006 post-launch support comparison**: Owner: product/support operations. Metric: categorized support requests related to navigation, sync, reports, payments, subscriptions, and accounting access per 1,000 monthly active users. Baseline window: the 30 days immediately before production rollout. Comparison window: the first 30 days immediately after rollout. Outcome remains pending until the post-launch window closes.

Rollout-only data operations and deployment requirements:

- **Entity `lastUsedAt` backfill**: Not executed locally in this pass because it is a mutating admin command and no safe Firestore emulator/target project was provided. Before rollout, run `npm --prefix functions run backfill:entity-last-used` against the approved target, run it twice, and retain scanned/updated counts proving idempotency.
- **Worker summary initialization**: `functions/package.json` now exposes `init:worker-accounting-summaries`. Before rollout, run the dry-run preview and then the write pass against the approved target. Retain counts for records scanned, target worker ledgers, summaries written, skipped invalid records, and unresolved legacy partials.

```powershell
firebase use prod

$env:WORKER_SUMMARY_INIT_DRY_RUN='true'
npm --prefix functions run init:worker-accounting-summaries
Remove-Item Env:\WORKER_SUMMARY_INIT_DRY_RUN

npm --prefix functions run init:worker-accounting-summaries
```

- **Targeted Firebase deploy required**: deploy `firestore.rules`, `firestore.indexes.json`, and functions covering notification read-state rules, metric-access rules, domain-accounting rules, workspace/project metrics recomputation, worker-summary recomputation, worker-status validation, worker partial-payment validation, the entity backfill command, and the worker summary initializer command.

```powershell
firebase deploy --only firestore:rules,firestore:indexes,functions --project wize-site --config firebase.deploy.json
```

### Live deployment to wize-site (prod) — 2026-06-16

| Step | Command | Result |
|------|---------|--------|
| Rules/functions emulator gate | `firebase emulators:exec --only firestore "npm --prefix functions test"` | **61 passed, 0 skipped** (rules validated pre-deploy) |
| Deploy rules + indexes | `firebase deploy --only firestore:rules,firestore:indexes` | Rules already current; indexes deployed (4 extra prod indexes left intact — no `--force`) |
| Deploy functions | `firebase deploy --only functions` | Deploy complete; all functions "no changes" — prod already matched repo (incl. `onWorkerAccountingWriteRecompute` + recompute triggers) |
| Worker-summary init (dry run) | `WORKER_SUMMARY_INIT_DRY_RUN=true npm --prefix functions run init:worker-accounting-summaries` | `{scanned:0, targetCount:0, summariesWritten:0, dryRun:true}` — no worker-accounting records in prod (no-op) |
| Entity `lastUsedAt` backfill (live) | `npm --prefix functions run backfill:entity-last-used` | `{scanned:0, updated:0, lastCursor:null}` — no legacy entities to backfill (idempotent script in place for future data) |

**Notes:** Admin scripts authenticate via `GOOGLE_APPLICATION_CREDENTIALS` (service-account key in repo root, gitignored + untracked). Production DB currently holds no entity or worker-accounting data, so both migrations are no-ops. No data or users were deleted (not required — migrations are additive/idempotent).

### T109 — Release verification & deployment requirements (completed 2026-06-16)

**Index audit** (`firestore.indexes.json`): valid JSON; every indexed collection group maps to an implemented query —
`project_metrics` (×7, global expense/income/net financial sort), `entities` (×3, directory paging by lastUsedAt/normalizedName/id), `notifications` (×3, targeted unread feed), `expenses`/`payments` (US2 lists), `worker_accounting_records` + `contractor/equipment/transport_provider_accounting_records` (domain accounting), `workers`/`worker_entries`, plus the maintained `*_summaries` collections. No indexes are defined for unimplemented queries. (Prod reported 4 extra indexes not in the file; left intact — deploy run **without** `--force` so nothing was deleted.)

**Backfill + summary init**: run and recorded above (Live deployment section) — both scanned 0 records (prod has no entity/worker-accounting data yet); scripts are idempotent and in place.

**Targeted deployment requirements** — a Firebase deploy is required when any of these change:
- **Notification rules** (`firestore.rules` `readAt` gating) → `firebase deploy --only firestore:rules`
- **Metric-access rules** (`workspace_metrics`/`project_metrics` accounting gating) → `firebase deploy --only firestore:rules`
- **Domain-accounting rules** (worker/contractor/equipment/transport accounting gating) → `firebase deploy --only firestore:rules`
- **Workspace/worker-summary recompute** (`onWorkerAccountingWriteRecompute`, `on*WriteRecompute`) → `firebase deploy --only functions`
- **Worker validation** (status / partial `paidAmount` rules + `createWorker`/`updateWorker`) → `firebase deploy --only functions` (+ rules)
- **New compound queries** (project-metric/report/entity-directory) → `firebase deploy --only firestore:indexes`

All of the above were deployed to `wize-site` on 2026-06-16 and validated by the 61-test emulator suite.
