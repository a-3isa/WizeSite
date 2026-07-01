# Review Findings — Buildozer Review Improvement Pack

Executing [review-plan.md](./review-plan.md). Severity: **blocker** (must fix before release) /
**major** (correctness or trust gap) / **minor** (cleanup / out-of-scope spirit gap) / **ok** (verified correct).

Date: 2026-06-16

---

## L1 — Static / anti-pattern sweep — ✅ done

| # | Severity | FR/area | Location | Finding | Suggested fix |
|---|----------|---------|----------|---------|---------------|
| L1-1 | fixed | FR-008 / accounting clarity | `lib/features/expenses/presentation/screens/expenses_screen.dart` | `_ExpenseSummaryCards` originally used hardcoded `currency: 'EGP'`. Non-EGP users (USD/SAR/AED) could see expense summary totals in the wrong currency. | Fixed on 2026-06-17: the screen now reads the user's default currency and passes it to `_ExpenseSummaryCards`. |
| L1-2 | fixed | FR-054 / constitution "no raw exception text" | Broad UI sweep | Raw `error.toString()` rendering existed beyond the original pack target screens. | Fixed on 2026-06-17: raw UI error rendering was sanitized with `appErrorMessage`; remaining grep hits are mapper/logging/classifier/debug paths, not user-facing UI. |
| L1-OK | ok | FR-025 (live pricing) | `plans_screen.dart:44,160,248` | Uses live `getPackages()`, handles `_packages.isEmpty`, renders live `package.priceString` — **no fabricated/fallback prices**. | — |
| L1-OK | ok | T075 (typed writes) | `domain_accounting_records_screen.dart` | No direct `.set/.update` writes remain; errors go through `appErrorMessage`. | — |
| L1-OK | ok | T100 (cleanup) | voice / reports / settings screens | No leftover "Play Test" / commented-out `Column` blocks; the one `kDebugMode` use (`settings_screen:234`) is the intentional Crashlytics TestFlight card. | — |

**L1 verdict:** PASS after fixes. The original currency-display bug and raw-error hygiene gap are resolved.

---

## Risk-1 — Accounting / money correctness — ✅ done

| # | Severity | Area | Finding |
|---|----------|------|---------|
| R1-OK | **ok** | Worker-summary cross-layer contract | The Dart `WorkerAccountingSummary.fromMap` reads `totalAmount, confirmedPaid, confirmedOutstanding, unresolvedLegacyCount, recordCount` and the functions (`index.ts:753-839`) write **exactly those names** — no silent-zero mismatch. |
| R1-OK | **ok** | paid/unpaid/partial derivation | Functions derivation (`index.ts:758-802`) mirrors the Dart `WorkerAccountingRecord.confirmedPaidAmount`: paid→full, unpaid→0, valid partial→paidAmount, missing/invalid partial→unresolved (excluded from confirmed). Consistent across layers. |
| R1-1 | fixed | invalid-data edge | For an **invalid** partial (`paidAmount >= amount`), functions mark it *unresolved* (`index.ts:782-788`) while Dart `confirmedPaidAmount` originally clamped to `amount`. Fixed on 2026-06-17: Dart now treats out-of-range partials as unresolved too, with regression coverage. |

**Risk-1 verdict: PASS after fix** — the money contract is sound, including the invalid partial edge.

---

## Risk-3 — Entity directory legacy visibility — ✅ NO BUG (initial finding RETRACTED)

**Correction (2026-06-17):** R3-1 and R3-2 were **false positives** in the first pass, caused by a `grep`
that searched for quoted `'id'`/`"id"` and therefore **missed the unquoted `patch.id`** in the backfill.
On reading the actual code:

- `functions/src/entity_last_used_backfill.ts:44-46` **does** write the stored `id`:
  `if (\`${data.id ?? ""}\` !== entityId) { patch.id = entityId; }` — so every legacy entity missing
  (or mismatching) `id` gets it backfilled, alongside `normalizedName` and `lastUsedAt`.
- `ensureEntity` writes `id`/`normalizedName`/`lastUsedAt` for **new** entities (`entity_repository.dart:234`).
- The functions unit test `entity_last_used_backfill.test.ts:10` **already asserts** `created?.id === "entity_created"`,
  and line 35 asserts a doc that already has `id` produces **no** patch.

⇒ After the backfill, legacy entities have all three order-by fields, so they are **not** excluded by
Firestore's `orderBy` — the directory feature works as specified (FR-021). **No fix required.**

*Residual (informational, minor):* the Dart `entity_repository_test.dart` relies on `fake_cloud_firestore`
which doesn't enforce the orderBy-missing-field exclusion, so that suite alone wouldn't catch a future
regression — but the **functions** test does cover the contract, so the behavior is protected.

---

## Risk-2 — Deployed Firestore rules gating — ✅ PASS

| Collection | Rule | Verdict |
|-----------|------|---------|
| `notifications` | read/update only `targetUserId`; update `hasOnly(["readAt"])` + `readAt is timestamp`; create/delete false | ✅ matches T026/FR |
| `workspace_metrics` / `project_metrics` | `read: canAccessAccounting`; `write: false` | ✅ accounting-gated, functions-only writes |
| `worker_accounting_summaries` | `read: canAccessAccounting`; `write: false` | ✅ |
| `worker_/contractor_/equipment_/transport_provider_accounting_records` | read/create/update/delete via `canAccessAccounting` + `validDomainAccountingRecord`/`validWorkerAccountingRecord` | ✅ |
| `workers` | read `inWorkspace`; create/update via `validWorkerWrite`/`validWorkerUpdate` (status validation); delete false | ✅ |
| `attachments` | `read: canAccessAccounting` | ✅ |
| `subscriptions` / `usage_counters` | `read: inWorkspace` (not accounting — correct, non-financial) | ✅ |

`canAccessAccounting` = role in `["owner","admin","accountingApproved"]`, so `member`/`entryOnly` are denied. Validated by the emulator suite. **Risk-2 verdict: PASS for the gated collections above — but see R2-1 below:** the audit initially missed that the `entities` collection had **no rule at all** (default-deny, found at runtime). That was the methodology gap (check for *missing* `match` blocks, not just the wrong ones). R2-1 is now fixed + deployed.

---

## Risk-4 — Test-quality spot-check — ✅ PASS

Spot-checked `sync_status_screen_test`, `plans_screen_test`, `workers_screen_test`, `dashboard_screen_test`: assertions are **behavioral**, not tautological — e.g. sync-status asserts the exact queued actions, localized failure reasons, and that individual retry re-enqueues the right id (`expect(retriedIds, ['failed_1'])`). The initial R3-2 concern was retracted after verifying that the functions backfill test protects the entity directory ordering contract.

---

## Executive summary

| Layer / Risk | Verdict |
|--------------|---------|
| L1 anti-pattern sweep | ✅ PASS after fixes (currency and raw UI errors resolved) |
| Risk-1 accounting/money | ✅ PASS after fix (cross-layer contract sound) |
| Risk-2 deployed rules | ✅ PASS (correct, server-enforced, 61-test validated) |
| Risk-3 entity directory legacy visibility | ✅ NO BUG — initial "2 major" finding **RETRACTED** (grep miss; backfill writes `id`, functions test covers it) |
| Risk-4 test quality | ✅ PASS |
| L2 coverage delta | ✅ review-significant gaps closed; residual uncovered lines are ordinary branch/UI coverage |

**Fixed:** L1-1 (expenses currency), R1-1 (invalid-partial alignment + test), L1-2 (plans_screen **and** the full
16-screen out-of-scope error-sanitization sweep — now app-wide), L2 provider/adapter coverage gaps, and the full
line-by-line FR trace against the 65 FR entries currently present in `spec.md`.
**Deferred (optional):** residual UI branch coverage listed in L2 below plus moderated/post-launch SC evidence that
cannot be completed from local automation alone.

**Verdict:** US1, US2, US3, US4 are correctly implemented and verified. The first-pass "directory" defect was a
**review error** (corrected). Latest gates: `flutter analyze lib test` is clean and
`flutter test --coverage --reporter compact` is **410 passing**; the remaining review work is only the optional
manual/post-launch evidence that cannot be completed from local automation alone.

---

## Fixes applied (2026-06-17)

| Finding | Resolution |
|---------|-----------|
| **R3-1 / R3-2** | **Retracted — false positives.** The backfill already writes `id` (`entity_last_used_backfill.ts:44-46`) and the functions test asserts it (`entity_last_used_backfill.test.ts:10,35`). No code change. |
| **L1-1** (major) | **Fixed.** `expenses_screen.dart` now derives `currency` from user settings in `build()` and passes it to `_ExpenseSummaryCards` (was hardcoded `'EGP'`). Payments screen was already correct. |
| **R1-1** (minor) | **Fixed.** Dart `confirmedPaidAmount` now treats an out-of-range partial (`paidAmount <= 0` or `>= amount`) as **unresolved** (returns null) instead of clamping — consistent with the functions writer. Added test `out-of-range partial paidAmount is unresolved`. |
| **L1-2** (in-scope part) | **Fixed.** `plans_screen.dart` now sanitizes purchase/paywall errors via `appErrorMessage` (was raw `e.toString()`). |
| **L1-2** (broad sweep) | **Superseded by completed sweep below.** The later L1-2 broad sweep sanitized the remaining user-facing raw error surfaces and added L2 coverage where needed. |
| **Google sign-in asset watch-item** | **Fixed.** Replaced the generated `assets/branding/google_g.png` placeholder with Google's official light square sign-in PNG from the pre-approved asset bundle. |

**Post-fix gate:** `flutter analyze lib test` → clean · `flutter test` → **399 passed**.

**Revised verdict at this checkpoint:** All pack-scope findings resolved. The headline "directory" defect was a
review error (grep miss), corrected. The optional broad error-sanitization sweep was still outstanding here and was
completed in the next section.

---

## L1-2 broad sweep — completed (2026-06-17)

Sanitized raw `error.toString()` / `_error = …toString()` across **16 out-of-scope screens** (~37 sites):
`add_entry_screen`, `forgot_password_screen`, `entity_detail_screen`, `add_expense_screen`,
`expense_detail_screen`, `add_payment_screen`, `payment_detail_screen`, `create_project_screen`,
`project_detail_screen`, `entity_aggregation_screen`, `profile_edit_screen`, `team_management_screen`,
`manage_subscription_screen`, `add_worker_entry_screen`, `add_worker_screen`, `worker_detail_screen` —
all now render `appErrorMessage(l10n, …)`. (`signup_screen` and `voice_review_screen` already used
dedicated error mappers — left as-is; `entity_detail_screen:94`'s `'$error'` interpolation also fixed.)

**Gate:** `flutter analyze lib test` → clean · `flutter test` → **399 passed**. Constitution "no raw
exception text" now holds app-wide. L1-2 fully resolved.

---

## L2 coverage delta — completed for review-significant gaps (2026-06-17)

Ran `flutter test --coverage --reporter compact` and mapped `coverage/lcov.info` against changed Dart files from
`git diff main -- lib` plus untracked `lib/` files.

**Gate:** `flutter test --coverage --reporter compact` → **410 passed** · `coverage/lcov.info` refreshed.

**Coverage map:** 165 LCOV source files · 132 changed Dart files · 129 changed Dart files with executable changed
lines · 1 changed Dart file absent from LCOV (`lib/main.dart`).

| # | Severity | Area | Finding | Resolution / next step |
|---|----------|------|---------|------------------------|
| L2-1 | **major** | T075 / generic domain-accounting writes | `domain_accounting_save_adapter.dart` initially had 0% changed-line coverage, despite replacing direct widget writes for contractor/equipment/transport accounting records. | **Fixed.** Added `test/features/common/domain_accounting_save_adapter_test.dart`, proving the adapter writes the generic owner fields and does **not** leak worker-only `paidAmount`. Refreshed changed-line coverage: 84.2% (16/19). |
| L2-2 | **major** | FR-036 / sync status recovery | `offline_queue_provider.dart` initially had 0% changed-line coverage for the pending/failed/dead-letter/resolved provider split; `sync_status_screen_test` bypassed the real providers by passing actions directly. | **Fixed.** Added `test/core/providers/offline_queue_provider_test.dart`, proving the providers split a shared sync stream by status and durable resolution. Refreshed changed-line coverage: 94.1% (32/34). |
| L2-3 | minor | L1-2 broad error-sanitization sweep | Several detail screens touched by the raw-error sweep initially had no direct LCOV execution on changed lines, and the entity-summary export paths still rendered raw `$error`. | **Fixed.** Added `test/widget/detail_screen_l2_coverage_test.dart` for expense detail sanitized errors, worker detail sanitized errors, success rendering for expense/worker/entity detail screens; added `test/widget/entity_aggregation_detail_screen_test.dart`; sanitized raw export errors in both entity-summary list/detail screens via `appErrorMessage`. Follow-up raw-error grep also found and fixed UI rendering in `archived_projects_screen.dart` and `voice_processing_screen.dart`; remaining grep hits are mapper/logging/classifier paths, not user-facing raw UI. Target files now appear in LCOV instead of being absent. Remaining uncovered lines are unpressed action branches such as duplicate/archive/attachment paths. |
| L2-4 | minor | Router / route construction | `lib/app/router.dart` changed lines were 0% in LCOV even though route behavior was covered indirectly by widget/navigation tests. | **Fixed.** Added `test/app/router_l2_coverage_test.dart`, which instantiates the real `appRouterProvider` with a mocked `FirebaseAuth`, asserts the review-pack routes exist, and covers authenticated workspace redirect behavior. Refreshed changed-line coverage: 23.1% (15/65); remaining route page-builder branches require full widget navigation and are not review blockers. |

**L2 verdict:** high-risk missing tests found by the coverage delta were closed, and the coverage pass caught two
additional raw export-error leaks that are now sanitized. Residual uncovered changed lines are ordinary UI branches
or platform-adapter paths, not new correctness defects for this review pack.

---

## L4 full FR trace - completed (2026-06-17)

`spec.md` currently contains **65** functional-requirement entries: `FR-001` through `FR-056` plus nine letter-suffix
requirements (`FR-003A`, `FR-005A`, `FR-008A`, `FR-012A`, `FR-019A`, `FR-021A`, `FR-034A`, `FR-034B`, `FR-037A`).
The earlier "66-FR" review note was stale; the trace below is against the live spec.

| FR | Verdict | Evidence |
|----|---------|----------|
| FR-001 | PASS | Four primary shell destinations are covered by T014, T020, T021, `test/widget/app_bottom_nav_shell_test.dart`, and `test/app/router_l2_coverage_test.dart`. |
| FR-002 | PASS | Notifications entry/read badge behavior is covered by T016, T023-T025, `test/widget/notifications_screen_test.dart`, and notification rules tests. |
| FR-003 | PASS | Dashboard quick-action ordering is covered by T019/T029 and `test/widget/dashboard_screen_test.dart`. |
| FR-003A | PASS | Denied-role dashboard behavior is covered by T018/T019, `test/features/dashboard/data/dashboard_providers_test.dart`, `test/widget/dashboard_screen_test.dart`, and rules gating. |
| FR-004 | PASS | Home refresh/retry behavior is covered by T019/T029 and dashboard widget/provider tests. |
| FR-005 | PASS | Shared loading/empty/recovery primitives and sanitized errors are covered by T006-T009, T012, L1-2, and L2 detail/entity tests. |
| FR-005A | PASS | Loading skeletons on dashboard/reporting surfaces are covered by `test/core/widgets/app_async_state_test.dart`, dashboard tests, and reports screen tests. |
| FR-006 | PASS | Voice capture duration/state-machine behavior is covered by T032, T039, T040, and `test/features/voice_expense/domain/voice_capture_state_test.dart`. |
| FR-007 | PASS | Recording progress/countdown is covered by T033/T041 and `test/widget/voice_record_screen_test.dart`. |
| FR-008 | PASS | Playback/review/rerecord flow is covered by T032/T033/T041 and voice record screen tests. |
| FR-008A | PASS | Live amplitude/visual recording feedback is covered by T033/T040/T041 and voice record screen tests. |
| FR-009 | PASS | User-currency fallback/forwarding is covered by T032/T033/T040/T041 and voice capture tests. |
| FR-010 | PASS | Individual filter-token removal is covered by T034/T035/T042/T044/T045 and expense/payment list tests. |
| FR-011 | PASS | Grouping-vs-filter presentation is covered by T034/T035/T042/T044/T045 and list widget tests. |
| FR-012 | PASS | Expense/payment empty CTAs are covered by T034/T035/T044/T045 and list widget tests. |
| FR-012A | PASS | Compact small-screen filters are covered by T034/T035/T044/T045 and list widget tests. |
| FR-013 | PASS | Print/share/save document handoff is covered by T010/T037/T046 and `test/features/reports/services/report_document_actions_test.dart`. |
| FR-014 | PASS | Project-scoped payment route context is covered by T038/T047 and `test/widget/payment_navigation_test.dart`. |
| FR-015 | PASS | Project status tabs and globally ordered financial sorts are covered by T049/T050/T060/T061 and project repository/screen tests. |
| FR-016 | PASS | Accounting-authorized financial summaries and denied-role fallback are covered by T049/T050/T060/T061 and project tests. |
| FR-017 | PASS | Archive confirmation is covered by T050/T061 and `test/widget/projects_screen_test.dart`. |
| FR-018 | PASS | Report project/date scope controls are covered by T051/T052/T062/T063/T066 and report provider/screen tests. |
| FR-019 | PASS | Scoped custom export data is covered by T053/T067 and `test/features/reports/services/report_export_data_builder_test.dart`. |
| FR-019A | PASS | Historical/archived report project selection is covered by T049/T051/T052/T064 and project/report selector tests. |
| FR-020 | PASS | Discoverable report export menu is covered by T052/T066 and reports screen tests. |
| FR-021 | PASS | Report chart/table/summary empty states are covered by T052/T066 and reports screen tests. |
| FR-021A | PASS | Single-chart PDF/share export is covered by T054/T065/T066 and `test/features/reports/services/report_chart_exporter_test.dart`. |
| FR-022 | PASS | Home Resources section and route handoff are covered by T056/T069-T071 and dashboard/resource directory tests. |
| FR-023 | PASS | Worker directory search/status is covered by T057/T072-T074 and worker status/screen tests. |
| FR-024 | PASS | Exact maintained worker accounting totals are covered by T058/T075/T076 and worker accounting tests. |
| FR-025 | PASS | Live subscription offers/unavailable retry state are covered by T079/T087-T089 and plans tests. |
| FR-026 | PASS | Recommended/best-value offer display is covered by T079/T087-T089 and plans tests. |
| FR-027 | PASS | Actual trial metadata display is covered by T079/T080/T087-T089 and RevenueCat/plans tests. |
| FR-028 | PASS | Plan comparison content is covered by T079/T087-T089 and plans tests. |
| FR-029 | PASS | Settings rollback/error recovery is covered by T081/T091 and settings tests. |
| FR-030 | PASS | App version/help/legal settings links are covered by T081/T091 and settings tests. |
| FR-031 | PASS | Expanded regional currencies are covered by T081/T091 and settings/localization tests. |
| FR-032 | PASS | Local sign-in assets are covered by T001/T002/T082/T092 and login tests. |
| FR-033 | PASS | Password reveal is covered by T082/T092 and login tests. |
| FR-034 | PASS | Inline sign-in validation is covered by T082/T092 and login tests. |
| FR-034A | PASS | Stable sign-in option slot during support checks is covered by T082/T092 and login tests. |
| FR-034B | PASS | Restored-session return path is covered by T082 plus `test/core/session_restore_service_test.dart`. |
| FR-035 | PASS | Sync status pending/failed/dead-letter/resolved list is covered by T083/T085/T093-T097 and sync status/provider tests. |
| FR-036 | PASS | Individual failed-item retry is covered by T083/T085/T093-T097 and L2 offline provider tests. |
| FR-037 | PASS | Offline/reconnecting banner stability is covered by T098 plus shell/dashboard tests. |
| FR-037A | PASS | Conflict-resolution outcome visibility is covered by T084/T094-T096 and offline conflict/sync status tests. |
| FR-038 | PASS | Profit/loss uses icon/text beyond color in dashboard/project coverage (T019/T050/T102/T103). |
| FR-039 | PASS | Central Add and quick-action semantic labels are covered by T015/T019/T102 and shell/accessibility tests. |
| FR-040 | PASS | RTL launcher/shell behavior is covered by T014/T015/T102 and accessibility RTL tests. |
| FR-041 | PASS | Long-running report/export progress feedback is covered by T052/T066/T067 and reports/export tests. |
| FR-042 | PASS | Scope discipline is enforced by the task breakdown and review corrections; no unrelated architecture replacement was introduced. |
| FR-043 | PASS | Bulk transaction archive confirmation/partial failure is covered by T036/T043-T045 and transaction bulk archive tests. |
| FR-044 | PASS | Friendly fallback summary labels are covered by T018/T019/T029 and dashboard tests. |
| FR-045 | PASS | Home upgrade placement is covered by T019/T029 and dashboard tests. |
| FR-046 | PASS | Large workspace progress/bounded browsing is covered by T049/T052/T060/T064/T077 and performance/report tests. |
| FR-047 | PASS | Arabic/English money/count formatting is covered by T003/T103 and formatter/localization tests. |
| FR-048 | PASS | Diagnostic termination confirmation is covered by T081/T091 and settings tests. |
| FR-049 | PASS | Localized labels/actions/errors across targeted screens are covered by T003/T004/T101 and localization/error-mapper tests. |
| FR-050 | PASS | Primary shell destination reachability is covered by T014/T020/T021 and router/shell tests. |
| FR-051 | PASS | Limit-reached upgrade path/copy is covered by T086/T090 and cap-hit integration tests. |
| FR-052 | PASS | Large project browsing overload is addressed by capped warm streams/paging and covered by T049/T060/T077. |
| FR-053 | PASS | Coherent dashboard refresh snapshot is covered by T018/T019/T028-T030 and dashboard/provider tests. |
| FR-054 | PASS | Cleanup/supporting engineering scope is covered by T100-T109, L1-2, L2, formatter/analyzer/test gates, and rollout notes. |
| FR-055 | PASS | Debug/hardcoded user-facing labels are covered by T100/T101 and the broad sanitization sweep. |
| FR-056 | PASS | Duplicate quick-action launches/repeated taps are covered by T014/T022/T030 and shell/prefetch tests. |

**L4 verdict:** no new release-blocking gaps were found in the FR trace. The trace confirms the existing task
mapping in `tasks.md` (`US1` T014-T031, `US2` T032-T048, `US3` T049-T078, `US4` T079-T099, and cross-cutting
T001-T013/T100-T109) is consistent with the implemented automated evidence. Manual success criteria remain governed
by `quickstart.md` rather than being declared passed from local code review.

---

## R2-1 — Missing `entities` Firestore rule (found at runtime, 2026-06-17) — ✅ FIXED + DEPLOYED

**Severity: blocker (production).** A real-device log showed the entity directory queries failing:
`entities where workspaceId==… and type==contractor order by -lastUsedAt,normalizedName,id → PERMISSION_DENIED`
(same for `equipmentProvider`, `transportProvider`).

**Root cause:** `firestore.rules` had **no `match /entities/{entityId}` block at all**, so the collection fell
through to the default **deny** — blocking both the directory list queries (T069/FR-021) and, silently,
`ensureEntity` autocomplete writes (which are swallowed by its try/catch).

**Audit miss:** my Risk-2 pass verified the collections that *had* rules but did not check for collections
that were **entirely missing** a rule — a gap in the methodology (should diff queried collections in code
against `match` blocks in the rules).

**Fix:** added
```
match /entities/{entityId} {
  allow read:   if inWorkspace(resource.data.workspaceId);           // directory + autocomplete
  allow create: if inWorkspace(request.resource.data.workspaceId) && workspaceId/name validated;
  allow update: if inWorkspace(resource.data.workspaceId) && workspaceId unchanged;  // lastUsedAt/id/attachments
  allow delete: if false;
}
```
Added emulator rules tests (member can read directory; non-member cannot; member can create/touch but not
reassign workspace) → **63 pass, 0 fail**. **Deployed `firestore:rules` to `wize-site`** — directory loads
again for workspace members.

---

## R2-1 follow-up — systematic missing-rule check + permanent guard (2026-06-21)

**Systematic diff** of every string-literal `.collection('…')` in `lib/` vs. every `match /…/` block in
`firestore.rules`: after the `entities` fix, **0 client collections are missing a rule block**. No
`collectionGroup` queries exist (so no group-scoped rule gap either).

**Permanent guard added:** `test/firestore_rules_coverage_test.dart` — scans `lib/` for `.collection('name')`
literals and **fails** if any lacks a `match /name/{…}` block in `firestore.rules`. This makes the R2-1
class of bug impossible to ship silently again.

**Final gate (all green):**
- `flutter analyze lib test` → clean
- `flutter test` → **411 passed** (incl. the new guard test)
- `firebase emulators:exec --only firestore "npm --prefix functions test"` → **63 pass / 0 fail** (1 pre-existing skip), rules incl. `entities` validated.

All review findings are now resolved (L1-1, R1-1, L1-2, R2-1) or retracted (R3). Remaining items are the
optional moderated/post-launch SC evidence that cannot be produced from local automation.

---

## L2 — Coverage delta (actually executed, 2026-06-21)

`flutter test --coverage` → overall **57.9%** line coverage (10,236 / 17,681 across 165 files — includes much
pre-existing app code). Coverage of the **pack's own logic-bearing code** is strong:

| File | Coverage |
|------|----------|
| `core/widgets/active_filter_bar.dart` | 100% |
| `features/dashboard/domain/dashboard_snapshot.dart` | 100% |
| `core/widgets/app_async_state.dart` | 98.5% |
| `features/workers/data/worker_accounting_repository.dart` | 97.1% |
| `features/workers/domain/worker_accounting_record.dart` | 95.8% |
| `core/utils/app_error_messages.dart` | 94.4% |
| `features/workers/domain/worker_models.dart` | 93.8% |
| `features/common/.../transaction_bulk_archive_controller.dart` | 89.6% |
| `features/voice_expense/.../voice_capture_controller.dart` | 82.8% |
| `features/reports/services/report_document_actions.dart` | 80.0% |
| `features/voice_expense/domain/voice_capture_state.dart` | 52% → **raised** (added value test for copyWith/getters/equality) |

**Genuinely-low spots are NOT pack-introduced logic:**
- `features/workers/data/worker_repository.dart` **12%** — the offline-merge `Stream.multi` infrastructure
  (pre-existing, stream-bound, impractical to unit-test; the pack's `statuses` filter *is* covered via `fetchWorkersPage`).
- `features/entities/data/entity_repository.dart` **67%** — `watch`/`search`/`ensureEntity` (pre-existing); the
  new directory paging (T068) is covered.
- `features/subscription/domain/purchase_coordinator.dart` **68%** — a 19-line data class; a couple of
  `copyWith` field branches unexercised (cosmetic).

**L2 conclusion:** every logic-bearing pack file has meaningful coverage; remaining low numbers are pre-existing
stream/infrastructure code and trivial data-class branches — no review-significant gap in the pack's behavior.
