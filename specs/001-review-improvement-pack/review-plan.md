# Implementation Review Plan — Buildozer Review Improvement Pack

**Purpose**: Verify that the tasks were **fully and correctly implemented** — independent of whether
they are marked `[X]` in `tasks.md`. A green checkbox and a passing test do not prove a requirement
was met: a test can assert the wrong thing, parallel-authored code may not match the task intent, and
deferred-then-completed backend needs real scrutiny.

**Created**: 2026-06-16
**Scope under review**: 65 functional requirements (FR-001…FR-056 incl. letter suffixes), 16 success
criteria (SC-001…SC-016), 2 contracts, ~104 Flutter test files + 6 Cloud Functions test files,
~445 changed files vs `main` + ~67 untracked.

---

## 0. Premise & correctness oracle

`tasks.md` checkboxes are **not** the oracle. The oracle, in priority order:

1. **`spec.md`** — FR-001…FR-056 and SC-001…SC-016
2. **`contracts/data-access-contract.md`** and **`contracts/ui-behavior-contract.md`**
3. **`.specify/memory/constitution.md`** — accounting correctness & traceability, offline/idempotency,
   scalable bounded reads, no raw exception text, role-based financial gating.

A task is "correctly implemented" only if **all** hold:
- the code satisfies its FR(s),
- a test **asserts that behavior** (not merely "renders"),
- it honors the contracts and the constitution.

The review explicitly distrusts "green test ⇒ correct".

---

> **Execution status (updated 2026-06-17):** risk-first pass, L2 coverage delta, and full FR trace executed — see [review-findings.md](./review-findings.md).
> ✅ L1 fixed/pass · ✅ Risk-1 fixed/pass · ✅ Risk-2 rules PASS · ✅ Risk-3 entity directory finding retracted · ✅ Risk-4 test quality PASS · ✅ L2 review-significant gaps closed · ✅ L4 FR trace complete for all 65 live FR entries.

## 1. Method — five layers (cheapest first)

| Layer | Catches | Tooling |
|------|---------|---------|
| **L1 Static / anti-pattern sweep** | Regressed anti-patterns the pack was meant to remove | grep for `error.toString()` in UI, hardcoded `'EGP'`, direct `firestore...set(`/`.update(` in widgets, fabricated/fallback prices, commented-out UI blocks, `kDebugMode`-gated production UI |
| **L2 Coverage delta** | Changed lines with **no test** | `flutter test --coverage` → `coverage/lcov.info`, intersect with `git diff --name-only main...HEAD` |
| **L3 Test-quality audit** | Tests that pass but assert the wrong thing / tautologies | Manual read of each new/changed test against its FR |
| **L4 Code trace** | Code that doesn't do what the FR says | Read implementation per FR and follow the data path end to end |
| **L5 Behavioral / backend** | Rules, functions, offline, conflict, RTL correctness | `firebase emulators:exec` rules run; read `firestore.rules`; device checks; idempotency re-runs |

---

## 2. Traceability matrix (the backbone)

Build one row per FR (65 in the current spec) and per SC (16):

```
FR | requirement summary | code file(s) | test file(s) | test asserts behavior? (Y/N) | verdict (PASS/WEAK/FAIL/MANUAL) | note
```

Seed from the **Requirement Traceability** section in `tasks.md`, then **independently confirm** each
mapping by opening the code + test. Any FR with no asserting test ⇒ **WEAK**, even if its task is `[X]`.

---

## 3. Per-user-story review batches (targets + traps)

### US1 — Shell & dashboard — FR-001–005A, 038–040, 044–045, 050, 053, 056
- **Trace**: `lib/core/widgets/app_bottom_nav_shell.dart`, `lib/app/router.dart`,
  `lib/features/add/presentation/screens/add_hub_screen.dart`,
  `lib/features/notifications/data/notification_repository.dart` + `notification_providers.dart`,
  `lib/features/dashboard/domain/dashboard_snapshot.dart`, `dashboard_providers.dart`,
  `functions/src/index.ts` (`workspace_metrics` recompute).
- **Traps**: Add branch truly not a hidden/unreachable tab; `DashboardSnapshot` makes **one** maintained
  read (not N raw weekly streams); a **denied role** triggers no financial reads (provider short-circuit,
  not just hidden UI); notification "missing `readAt` = unread" is asserted; badge count is bounded.

### US2 — Voice + lists / bulk archive — FR-006–014, 043
- **Trace**: `lib/features/voice_expense/presentation/controllers/voice_capture_controller.dart`,
  `voice_record_screen.dart`, `lib/core/widgets/active_filter_bar.dart`,
  `lib/features/common/presentation/controllers/transaction_bulk_archive_controller.dart`,
  `expenses_screen.dart`, `payments_screen.dart`,
  `lib/features/reports/services/report_document_actions.dart`.
- **Traps**: 60s auto-stop and **user currency forwarded** (no hardcoded `'EGP'`); bulk archive uses the
  **existing archive mutations** (offline-safe) and partial failure keeps only failed records selected;
  export reaches **both** print and share; one-token removal removes **only** that filter;
  project-scoped payment list→detail→edit→add return behavior preserved.

### US3 — Projects / reports / entities / workers / accounting — FR-015–024, 041, 046, 047, 052  ← HIGHEST RISK
- **Trace**: `lib/features/projects/data/project_repository.dart` (50-cap + global `project_metrics`
  paging), `lib/features/reports/data/reports_providers.dart` (single scope), `report_scope.dart`,
  `lib/features/entities/data/entity_repository.dart` (directory paging),
  `lib/features/workers/domain/worker_models.dart` (status),
  `worker_accounting_record.dart` (paidAmount + summary), `worker_accounting_repository.dart`,
  `functions/src/worker_accounting_summary_initializer.ts`, `functions/src/index.ts` (recompute),
  `functions/src/entity_last_used_backfill.ts`, `firestore.rules`.
- **Traps to hammer (priority)**:
  1. **Entity directory legacy visibility (reviewed/retracted as a bug):** directory queries `orderBy('id')` /
     `orderBy('lastUsedAt')`. Firestore **excludes** docs missing the order-by field. The review verified the
     backfill writes **both** `id` and `lastUsedAt` onto legacy entities, and the functions test protects this
     contract.
  2. **Money correctness:** `confirmedPaidAmount` / `WorkerAccountingTotals` exclude unresolved legacy
     partials in **every** consumer; the **functions** summary writer emits the exact field names the
     Dart `WorkerAccountingSummary.fromMap` reads (`confirmedPaid`, `confirmedOutstanding`,
     `unresolvedLegacyCount`, `recordCount`).
  3. **Page-size independence:** worker totals come from the maintained summary, not the 50-row page.
  4. **Server-side gating:** denied roles are denied by **rules**, not merely client-hidden.

### US4 — Subscription / settings / login / sync — FR-025–037A, 048, 049, 051, 055
- **Trace**: `lib/features/subscription/domain/purchase_coordinator.dart`,
  `data/revenuecat_purchase_coordinator.dart`, `presentation/screens/plans_screen.dart`,
  `limit_reached_screen.dart`, `settings_screen.dart`, `login_screen.dart`,
  `lib/core/services/offline_action_queue.dart`, `offline_queue_coordinator.dart`,
  `workspace_mutation_service.dart`, `lib/features/settings/presentation/screens/sync_status_screen.dart`,
  `lib/core/providers/offline_queue_provider.dart`.
- **Traps**: no fabricated packages/prices (live offers only); conflict resolution persists a **durable**
  "newer-version-kept" outcome that the sync-status UI shows; individual retry actually re-enqueues a
  failed action; login uses **local** branding assets. The Google sign-in icon has been replaced with the
  official light square asset from Google's pre-approved sign-in asset bundle.

---

## 4. Cross-cutting audits

- **Backend / security (deployed live to prod):**
  - Re-run `firebase emulators:exec --only firestore "npm --prefix functions test"` (expect 61 pass).
  - **Read** `firestore.rules` per gated collection and confirm a member/entry-only role is **denied**
    (not just unindexed): notifications `readAt`-only updates; `workspace_metrics`/`project_metrics`
    accounting-role-only reads; domain-accounting collections; worker `status` + partial `paidAmount`
    write validation.
- **Localization / RTL — FR-042, FR-054, SC-008:** coverage test passes, but spot-check that surfaced
  strings use keys (no hardcoded English) and Arabic values are not English fallbacks.
- **Offline / idempotency (constitution):** enqueue the same mutation twice → last-saved-change-wins,
  no duplicate; conflict skip is durable.
- **Scalable reads (constitution):** no unbounded `.snapshots()` on normal screens; the perf test
  (`test/features/performance/accounting_query_performance_test.dart`) asserts **real bounds**, not
  constants.

---

## 5. Risk-prioritized execution order (dangerous first)

1. **Accounting / money correctness** — US3 paidAmount, totals, maintained summaries (trust-critical).
2. **Deployed Firestore rules** — already live in prod; wrong gating = data exposure.
3. **Entity directory legacy-visibility drop-out** (§3 US3 trap 1) — reviewed and retracted as a bug.
4. **Collaborator-authored widget tests** — highest "passes but asserts nothing" risk.
5. Everything else, ordered by L2 coverage gaps.

---

## 6. Tooling / commands

```powershell
# L2 coverage
flutter test --coverage
# then map coverage/lcov.info against:
git diff --name-only main...HEAD

# L1 anti-pattern sweeps (examples)
#   raw exception text in UI:        grep error.toString() under lib/features/**/presentation
#   hardcoded currency:              grep "'EGP'" under lib (outside fallback constants)
#   direct firestore writes in UI:   grep "collection(" / ".set(" under **/presentation/screens
#   fabricated prices:               grep fallback/hardcoded price strings in plans_screen
#   leftover debug UI:               grep kDebugMode / commented-out widget blocks

# L5 backend rules
firebase emulators:exec --only firestore "npm --prefix functions test"
```

---

## 7. Deliverable & exit criteria

- **Findings log** row format: `severity (blocker/major/minor) | FR | file:line | what's wrong | suggested fix`.
- **Exit criteria**:
  - every FR is PASS or has a logged finding;
  - every SC is PASS or MANUAL-pending (with the named evidence protocol from `quickstart.md` §7);
  - zero open **blockers**;
  - no uncovered changed lines in accounting or rules code.

---

## 8. Known watch-items already identified (seed the findings log)

- **`assets/branding/google_g.png`** — resolved 2026-06-17 by replacing the generated placeholder with
  Google's official light square sign-in PNG from the pre-approved asset bundle.
- **Entity directory legacy visibility** — resolved/retracted in `review-findings.md`; the backfill writes
  `id` + `lastUsedAt`, and the functions test protects the contract.
- **fake_cloud_firestore cursor limitation** — accepted as a tooling limitation; release validation now includes
  the emulator rules/functions gate and the directory behavior remains protected by functions/backfill coverage.
- **SC-006 (post-launch support volume)** and the moderated usability / timed performance cohorts are
  evidence-gathering items, not code — track via `quickstart.md` §7, not as implementation defects.
