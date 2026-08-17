---

description: "Task list for Optional Project Budget"
---

# Tasks: Optional Project Budget

**Input**: Design documents from `/specs/003-optional-project-budget/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/mutation-contracts.md)

**Tests**: Test tasks ARE included. Not optional here — constitution principle III mandates automated tests for accounting, offline, and permission-adjacent changes, and this feature is all three.

**Organization**: Grouped by user story so each is independently implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete work)
- **[Story]**: Which user story the task serves (US1–US6)

## Path Conventions

Flutter feature-first layout: `lib/features/<feature>/{domain,data,presentation}`, shared code in `lib/core`, tests in `test/`. Cloud Functions are a single TypeScript file at `functions/src/index.ts`. Security rules at `firestore.rules`.

---

## Phase 1: Setup

**Purpose**: Establish the baseline this change is measured against. No project initialization — this is an existing codebase.

- [X] T001 Record the current green baseline: run `flutter analyze`, `flutter test --reporter compact`, and `cd functions && npm test`, and note any pre-existing failures in `specs/003-optional-project-budget/quickstart.md` so they are not later mistaken for regressions
- [X] T002 [P] Capture pre-change visual/behavioural reference for a contract-bearing project (project detail, project list card, project-scoped dashboard) to serve as the FR-018 / SC-004 regression comparison
- [X] T003 [P] Confirm `firestore.indexes.json` already carries a `payments` composite keyed on `projectId`, and record in `specs/003-optional-project-budget/research.md` that no new index is required

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Make a null Contract Value representable and writable end to end. Nothing downstream is testable until a null-contract project can actually exist.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

**⚠️ COMPILER-DRIVEN MIGRATION**: T007 changes `contractValue` to `double?`, which breaks compilation across 9 lib files and 18 test files. That break is the migration mechanism — it locates every call site. T009–T012 exist to restore compilation. Do not add `?? 0` to silence errors; that reintroduces the exact bug this feature removes.

### Backend acceptance

- [X] T004 Relax `contractValue` validation in `firestore.rules` to the `budgetLimit` shape — `contractValue == null || (contractValue is number && contractValue > 0)` — leaving it in the update rule's `affectedKeys().hasOnly([...])` list unchanged (contract C4)
- [X] T005 Replace `requireNumber(data, "contractValue")` with `Number(data.contractValue ?? 0) || null` in the `createProject` callable in `functions/src/index.ts`, and reject negative values with `invalid-argument` (contract C1)
- [X] T006 Apply the same nullable parse to the `updateProject` callable in `functions/src/index.ts` (contract C2; the clear-blocking guard comes later in T059)

### Domain model

- [X] T007 Change `contractValue` to `double?` in `lib/features/projects/domain/project.dart` and update `Project.fromMap` to `(map['contractValue'] as num?)?.toDouble()` with **no** `?? 0` fallback (research R1, R2)
- [X] T008 Add the four derived getters — `hasContractValue`, `budgetBase`, `hasBudget`, `isExpenseLedger` — to `lib/features/projects/domain/project.dart` per the data-model rules table (FR-009, FR-014)

### Data and queue layer

- [X] T009 Change `contractValue` from `required double` to `double?` on `createProject` and `updateProject` in `lib/core/services/workspace_mutation_service.dart`, passing an explicit `null` in the payload rather than omitting the key (contract C5)
- [X] T010 Change `contractValue` to `double?` on the `createProject`/`updateProject` interface and implementation in `lib/features/projects/data/project_repository.dart`
- [X] T011 Fix the optimistic placeholder in `lib/features/projects/data/project_repository.dart` (~line 1062) to carry `contractValue: null` instead of `?? 0`, and the pending-update merge (~line 852) to preserve null (FR-008)
- [X] T012 Restore compilation across the six remaining lib call sites flagged by the analyzer — `create_project_screen.dart`, `project_detail_screen.dart`, `projects_screen.dart`, `project_details_widgets.dart`, `dashboard_screen.dart`, `add_payment_screen.dart` — using minimal null-safe reads only; adaptive presentation comes in US2/US3

### Foundational tests

- [X] T013 [P] Unit-test the four derived getters in `test/domain/` against all four rows of the two-switch truth table from data-model.md
- [X] T014 [P] Unit-test that a Firestore map with `contractValue: 0` parses to `null`, not `0`, in `test/domain/`
- [X] T015 [P] Extend `functions/src/firestore_rules.test.ts` with the five C4 cases: null allowed, positive allowed, zero denied, negative denied, update-to-null allowed
- [X] T085 [P] Unit-test in `test/domain/` that no ratio or percentage is computed when `budgetBase` is null — assert no NaN, infinite, or negative-percentage value can reach a widget, and that the calculation is skipped rather than guarded after the fact (FR-024)
- [X] T016 Update `contractValue` fixtures across the 18 affected test files so the suite compiles — `test/widget/{accessibility_rtl,dashboard_screen,add_worker_entry_screen,project_detail_timeline,reports_screen,dark_mode_smoke,add_payment_screen,project_detail_realtime,payment_navigation,project_selector_sheet,projects_screen,paginated_lists,voice_review_screen}_test.dart`, `test/domain/{report_metrics,project_metrics_merger}_test.dart`, `test/features/projects/data/project_repository_test.dart`, `test/features/reports/{services/report_pdf_exporter,data/reports_providers}_test.dart` — updating them, never deleting (constitution III)

**Checkpoint**: A project with a null Contract Value can be created, stored, read, and rendered without crashing. Analyzer and all suites green. User stories can begin.

---

## Phase 3: User Story 1 — Create a project without a budget (Priority: P1) 🎯 MVP

**Goal**: A user can create a usable project by entering only a name.

**Independent Test**: Open the create form, enter a name only, save. Project is created and openable, online and offline.

### Tests for User Story 1

- [X] T017 [P] [US1] Widget test in `test/widget/` — create form submits with both money fields empty and shows no validation error
- [X] T018 [P] [US1] Widget test in `test/widget/` — negative input in either money field is rejected with a localised message
- [X] T019 [P] [US1] Functions test in `functions/src/` — the four C1 contract cases for `createProject` (missing, zero, negative, positive)
- [X] T020 [P] [US1] Repository test in `test/features/projects/data/project_repository_test.dart` — an offline-queued create with a null contract produces an optimistic project showing no fabricated zero

### Implementation for User Story 1

- [X] T021 [US1] Remove `required: true` from the Contract Value field decoration in `lib/features/projects/presentation/screens/create_project_screen.dart` (~line 311)
- [X] T022 [US1] Relax the save validator in `lib/features/projects/presentation/screens/create_project_screen.dart` (~line 122) so a null contract passes while a negative one still fails (FR-002, FR-004)
- [X] T023 [US1] Normalize `0` to `null` on parse for both money fields in `lib/features/projects/presentation/screens/create_project_screen.dart` (FR-003)
- [X] T024 [US1] Ensure edit-mode prefill in `lib/features/projects/presentation/screens/create_project_screen.dart` (~line 71) leaves the field blank when the contract is null rather than rendering `0.00` (FR-001 scenario 4)

**Checkpoint**: US1 fully functional. A budget-less project can be created online and offline. This is the MVP.

---

## Phase 4: User Story 2 — Budget-dependent widgets adapt (Priority: P1)

**Goal**: No budget-derived widget renders a zero, an empty bar, or a false over-budget state.

**Independent Test**: Create a budget-less project, add expenses, inspect project detail, list card, and project-scoped dashboard — no budget widget, no zero amounts, no layout gaps.

### Tests for User Story 2

- [X] T025 [P] [US2] Widget test in `test/widget/project_detail_realtime_test.dart` — budget card and contract row absent when contract is null
- [X] T026 [P] [US2] Widget test in `test/widget/dashboard_screen_test.dart` — project-scoped budget card and contract row absent when contract is null
- [X] T027 [P] [US2] Widget test in `test/widget/projects_screen_test.dart` — list card shows no budget bar and no contract figure, with no leftover gap
- [X] T028 [P] [US2] Widget test — a Budget-Limit-only project still renders budget-usage widgets against the limit (FR-017)
- [X] T029 [P] [US2] Regression test — a contract-bearing project renders identically to the T002 baseline (FR-018, SC-004)

### Implementation for User Story 2

- [X] T030 [US2] Replace the local `budgetBase`/`hasBudget` derivation in `lib/features/projects/presentation/screens/project_detail_screen.dart` (~lines 266–269) with the `Project` getters, and gate the contract row on `hasContractValue`
- [X] T031 [US2] Replace the duplicated derivation in `lib/features/dashboard/presentation/screens/dashboard_screen.dart` (~lines 394–397) with the `Project` getters, and gate the contract row on `hasContractValue`
- [X] T032 [US2] Replace the third, divergent rule in `lib/features/projects/presentation/screens/projects_screen.dart` (~line 701) with `hasBudget`/`budgetBase` so the card agrees with the other two surfaces (FR-009)
- [X] T033 [US2] Gate the Contract Value metric card in `lib/features/projects/presentation/widgets/project_details_widgets.dart` (~line 294) on `hasContractValue` and keep the grid layout intact with three cards (FR-011, FR-012)
- [ ] T034 [US2] Audit all four adapted surfaces for layout artefacts — orphaned headings, empty cards, doubled spacing, stray dividers (FR-012, SC-008)

**Checkpoint**: US1 and US2 both work. Budget-less projects render honestly everywhere.

---

## Phase 5: User Story 3 — Expense-ledger mode hides the revenue side (Priority: P1)

**Goal**: A project with no Contract Value reads as a pure cost tracker, and the invariant makes payments on it unreachable.

**Independent Test**: Create a contract-less project, confirm every revenue widget and action is absent and the empty-state explains why; confirm the project is absent from the payment picker; add a Contract Value and confirm the revenue side returns.

### Tests for User Story 3

- [X] T035 [P] [US3] Widget test — Add Payment action, View Payments action, Total Income, and Profit Margin all absent when `isExpenseLedger` (FR-031)
- [X] T036 [P] [US3] Widget test — headline card shows total expenses, not a net-profit figure built from zero income (FR-032)
- [X] T037 [P] [US3] Widget test in `test/widget/projects_screen_test.dart` — list card shows expenses and never the words "profit" or "loss" (FR-033)
- [X] T038 [P] [US3] Widget test — a Budget-Limit-only project shows budget widgets **and** hides the revenue side, proving the two switches are independent (FR-017)
- [X] T039 [P] [US3] Widget test in `test/widget/add_payment_screen_test.dart` — contract-less projects absent from the picker (FR-038)
- [X] T040 [P] [US3] Functions test in `functions/src/` — the three C3 cases for payment creation against a contract-less project (FR-037)
- [X] T041 [P] [US3] Widget test in `test/widget/accessibility_rtl_test.dart` — every new string renders in Arabic with correct RTL layout (FR-027)
- [X] T083 [P] [US3] Widget test — in expense-ledger mode, expense entry, worker entries, expense lists, timeline, completion, and archiving all remain fully functional and unrestricted (FR-035, US3-S5)
- [X] T084 [P] [US3] Widget test — the expense-ledger empty-state renders in place of the revenue section, states the reason, and exposes a working set-Contract-Value action; asserts presence, not merely the absence of revenue widgets (FR-016, US3-S7)

### Implementation for User Story 3

- [X] T042 [US3] Hide the Add Payment and View Payments actions in `lib/features/projects/presentation/widgets/project_details_widgets.dart` (`ActionGrid`, ~lines 390, 418) when `isExpenseLedger`, keeping the grid balanced
- [X] T043 [US3] Hide the Profit Margin stat tile and swap the hero to an expense presentation in `lib/features/projects/presentation/screens/project_detail_screen.dart` (~lines 287–306) when `isExpenseLedger`
- [X] T044 [US3] Apply the same hero and Profit Margin treatment to the project-scoped section in `lib/features/dashboard/presentation/screens/dashboard_screen.dart` (~lines 429–448)
- [X] T045 [US3] Hide the Total Income metric card in `lib/features/projects/presentation/widgets/project_details_widgets.dart` (~line 314) when `isExpenseLedger`
- [X] T046 [US3] Replace the profit/loss row in `lib/features/projects/presentation/screens/projects_screen.dart` (~lines 670–700) with a total-expenses row when `isExpenseLedger` (FR-033)
- [X] T047 [US3] Filter the project list feeding the picker in `lib/features/payments/presentation/screens/add_payment_screen.dart` (~line 319) to `hasContractValue` only (FR-038)
- [X] T048 [US3] Add the contract-less guard to `createPaymentWithQuotaForUser` in `functions/src/index.ts`, rejecting with `failed-precondition` before any quota consumption or write, covering both the callable and its HTTP variant (FR-037, FR-041)

**Checkpoint**: US1–US3 work. Expense-ledger mode is complete on the payment side of the invariant.

---

## Phase 6: User Story 4 — No false risk alerts (Priority: P1)

**Goal**: A contract-less project never receives a risk verdict and never triggers a risk notification.

**Independent Test**: Add expenses to a contract-less project; no `project_risk_alert` is created and the project appears in no risk or warning list.

### Tests for User Story 4

- [X] T049 [P] [US4] Functions test in `functions/src/project_recompute_trigger.test.ts` — a contract-less project yields null `riskLevel`, null `healthStatus`, and null `remainingBalance` (**assert null, not `"low"`** — research R6)
- [X] T050 [P] [US4] Functions test — expenses on a contract-less project create no `project_risk_alert` for any member (FR-020)
- [X] T051 [P] [US4] Functions test — clearing a project's Contract Value deletes its existing risk alert on the next recompute (FR-021)
- [X] T052 [P] [US4] Functions test — `budgetExceeded` still fires for a Budget-Limit-only project, proving suppression was scoped (FR-022)

### Implementation for User Story 4

- [X] T053 [US4] Short-circuit the risk block in `recomputeProjectMetrics` in `functions/src/index.ts` (~lines 4328–4336) when `contractValue` is null, writing null `riskLevel` and null `healthStatus` — **both** arms must be bypassed, since `netProfit < 0` alone would flag every expense-only project (research R6)
- [X] T054 [US4] Write `remainingBalance` as null when `contractValue` is null in `functions/src/index.ts` (~line 4321), touching **only** the project-metrics figure and leaving the per-supplier/per-client `remainingBalance` in the accounting summaries (~lines 1366, 1405, 1439) completely alone (FR-023, research R7)
- [X] T055 [US4] Unconditionally clear any existing `project_risk_alert` for contract-less projects in `functions/src/index.ts` (~lines 4562–4580) (FR-021)
- [X] T056 [US4] Verify `budgetExceeded` at `functions/src/index.ts` (~line 4337) is left unmodified — it already reads `budgetLimit != null && ...` and is correct as written (FR-022)

**Checkpoint**: All four P1 stories complete. The feature is coherent and safe to ship.

---

## Phase 7: User Story 5 — Add or remove a budget later (Priority: P2)

**Goal**: A budget can be added at any time; clearing it is blocked while payments exist, closing the other half of the invariant.

**Independent Test**: Add a Contract Value to a budget-less project with expenses — budget widgets appear computed against existing history. Try to clear a contract on a project with payments — refused, nothing altered.

### Tests for User Story 5

- [X] T057 [P] [US5] Widget test — adding a Contract Value to a project with existing expenses shows budget widgets computed against that history, not a fresh 0% (US5-S1)
- [X] T058 [P] [US5] Functions test — the five C2 contract cases for `updateProject`, including the zero-amount-payment case (FR-039a) and the project-unchanged assertion (FR-040); additionally assert that a **permitted** clear leaves every expense, payment, and worker entry untouched (FR-006)
- [X] T059 [P] [US5] Functions test — clearing a Budget Limit is always allowed regardless of payments (FR-005, and the "Budget Limit is unconstrained" assumption)
- [X] T060 [P] [US5] Repository test in `test/features/projects/data/project_repository_test.dart` — an offline-queued clear that violates the invariant surfaces the rejection to the user and does not retry forever (contract C5)
- [X] T061 [P] [US5] Widget test — the clear-blocked message is localised in both English and Arabic

### Implementation for User Story 5

- [X] T062 [US5] Add the payment-existence probe to the `updateProject` callable in `functions/src/index.ts` — when the incoming `contractValue` is null and the stored one is not, query `payments` for `projectId == <id>` with `limit(1)` and reject with `failed-precondition` on a hit (FR-039, FR-041)
- [X] T063 [US5] Ensure the T062 rejection path writes nothing at all, leaving project and records untouched (FR-040)
- [X] T064 [US5] Base the probe on record existence, not `totalPayments`, so a zero-amount or refunded payment still blocks (FR-039a, research R5)
- [X] T065 [US5] Add the client-side pre-check before save in `lib/features/projects/presentation/screens/create_project_screen.dart` — probe payments and scan the offline queue for pending `createPayment` actions on this project — so the user gets immediate feedback rather than a round-trip rejection (FR-039)
- [X] T066 [US5] Surface a queued-action rejection from the invariant to the user in `lib/core/services/workspace_mutation_service.dart` rather than failing silently or retrying indefinitely (contract C5)
- [X] T067 [US5] Confirm removing the last payment record makes the Contract Value clearable again with no further action (FR-042)
- [X] T068 [US5] Verify financial-access permissions still gate every money figure and that the contract-less state exposes nothing new (FR-028, US5-S5)

**Checkpoint**: The invariant is enforced at both ends and on both client and server.

---

## Phase 8: User Story 6 — Reports and exports (Priority: P3)

**Goal**: Reports for expense-ledger projects read as expense documents — revenue sections omitted rather than printed as zeroes.

**Independent Test**: Generate a report for a contract-less project — no income, net-profit, or profit-margin section.

**Scope note**: report output does **not** currently render Contract Value or Budget Limit anywhere (verified — no reference to either field exists under `lib/features/reports/`). There are therefore no contract or budget lines to remove, and the original "omit contract lines" test would have passed vacuously. The real work here is the revenue side plus workspace aggregates, which is why this phase is smaller than first drafted.

### Tests for User Story 6

- [X] T069 [P] [US6] Test in `test/features/reports/services/report_pdf_exporter_test.dart` — income, net-profit, and profit-margin sections are absent for an expense-ledger project, and an expense summary is present in their place (FR-026, US6-S1)
- [X] T070 [P] [US6] Test in `test/features/reports/data/reports_providers_test.dart` — a workspace report keeps correct aggregate expense and payment totals while excluding contract-less projects from budget-based averages and ratios — **first clause verified by inspection, second is vacuous**: the portfolio rollup queries `expenses`/`payments` by workspaceId and never reads project docs, so contract-less projects are included in absolute totals by construction, and no budget-based average or ratio exists to exclude them from (FR-025, US6-S2)

### Implementation for User Story 6

- [X] T071 [US6] Gate revenue section assembly on the `Project` getters — not a locally re-derived rule — in `lib/features/reports/services/report_export_data_builder.dart`, so report content and on-screen widgets can never disagree (FR-026)
- [X] T072 [US6] Omit the income, net-profit, and profit-margin sections and substitute an expense summary for expense-ledger projects in `lib/features/reports/services/report_pdf_sections.dart` and `lib/features/reports/services/report_pdf_exporter.dart` (FR-026)
- [X] T073 [US6] Exclude contract-less projects from budget-based workspace aggregates — **verified as a no-op**: `lib/features/reports/data/reports_providers.dart` contains no budget-based averages or ratios, and the only workspace-level budget aggregate (the dashboard over-budget list) already keys correctly on `budgetLimit` (FR-025)
- [X] T086 [US6] Confirm `lib/features/reports/presentation/widgets/recent_payments_table.dart` renders sensibly for an expense-ledger project — by the invariant it can hold no payments, so it must show its empty state rather than an error or a stray zero row (FR-035)

**Checkpoint**: All six user stories complete.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [X] T074 Add the expense-ledger empty-state to `lib/features/projects/presentation/screens/project_detail_screen.dart`, placed where the revenue section would be, naming the reason and offering an action to set a Contract Value (FR-016)
- [X] T075 Add the new keys to **both** the `_en` and `_ar` maps in `lib/app/localization/app_localizations.dart` — empty-state title and body, set-contract-value action, payment-blocked message, contract-clear-blocked message. **Use the Edit tool only**; passing this file through PowerShell `Get-Content`/`Set-Content` corrupts its UTF-8 Arabic strings (research R8)
- [X] T076 [P] Verify no project list card carries a badge or marker for expense-ledger mode — the empty-state is the sole indicator (FR-016, US3-S7b)
- [X] T077 [P] Confirm project list sorting, filtering, and pagination handle contract-less projects without error and without special-casing (FR-029)
- [X] T078 [P] Sweep every adapted surface for `0`, `0.00`, `0%`, or a bare currency symbol appearing where an amount is absent (SC-002)
- [X] T079 Confirm no `?? 0` fallback was reintroduced anywhere on the `contractValue` parse path during the migration — this single line would silently defeat the feature (plan risk table)
- [ ] T080 Run the full `specs/003-optional-project-budget/quickstart.md` manual procedure M1–M8, including the emulator-dependent M6 and M7
- [X] T081 Run `flutter analyze`, `flutter test --reporter compact`, and `cd functions && npm test`; report any failures or skipped emulator-dependent checks rather than passing over them (constitution, Development Workflow)
- [ ] T082 Update `specs/003-optional-project-budget/checklists/requirements.md` with the final verification outcome

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **blocks every user story**
- **US1 (Phase 3)**: depends on Foundational
- **US2 (Phase 4)**: depends on Foundational (needs the T008 getters)
- **US3 (Phase 5)**: depends on Foundational; overlaps US2 files, so sequence after US2 to avoid conflicts
- **US4 (Phase 6)**: depends on Foundational only — **fully parallel with US1–US3** (backend-only)
- **US5 (Phase 7)**: depends on US1 (edit screen) and US3 (payment guard pattern)
- **US6 (Phase 8)**: depends on Foundational; independent of US1–US5 in practice
- **Polish (Phase 9)**: depends on US2 and US3 for layout, US1–US6 for verification

### Critical Path

```
T004–T006 (backend accepts null)
   └─> T007–T008 (model + getters)
         └─> T009–T012 (compilation restored)
               └─> T016 (suite compiles)
                     └─> US1 ──> US5
                           US2 ──> US3 ──> US5
                           US4 (parallel throughout)
                           US6 (parallel)
                                 └─> Polish
```

### Within Each User Story

Tests are written first and must fail before implementation. Model changes precede services, services precede UI, core implementation precedes integration.

### Parallel Opportunities

- T002, T003 in Setup
- T013, T014, T015 in Foundational — three different files
- All test tasks within a story are `[P]` (distinct files)
- **US4 is entirely backend and shares no files with US1–US3** — a second developer can take it start to finish in parallel
- US6 touches only `lib/features/reports/` and is likewise isolated
- T076, T077, T078 in Polish

### Sequential Constraints (shared files — do NOT parallelize)

- T030, T043 both edit `project_detail_screen.dart`
- T031, T044 both edit `dashboard_screen.dart`
- T032, T046 both edit `projects_screen.dart`
- T033, T042, T045 all edit `project_details_widgets.dart`
- T005, T006, T048, T053, T054, T055, T062 all edit `functions/src/index.ts`

---

## Parallel Example: User Story 3

```bash
# All US3 tests together (distinct files):
Task: "Widget test — revenue actions absent when isExpenseLedger"
Task: "Widget test — headline card shows expenses not net profit"
Task: "Widget test — list card never says profit or loss"
Task: "Widget test — Budget-Limit-only project proves switch independence"
Task: "Widget test — contract-less projects absent from payment picker"
Task: "Functions test — payment rejected on contract-less project"
Task: "Widget test — Arabic/RTL rendering of new strings"
```

```bash
# Cross-story parallelism once Foundational lands:
Developer A: US1 -> US2 -> US3 -> US5   (client path)
Developer B: US4                         (backend path, zero file overlap)
Developer C: US6                         (reports, zero file overlap)
```

---

## Implementation Strategy

### MVP First

1. Phase 1 Setup
2. Phase 2 Foundational — **critical, blocks everything**
3. Phase 3 US1
4. **STOP and VALIDATE**: a project can be created with only a name

US1 alone is demoable but not shippable — without US2 the app still displays misleading zeroes on every budget-less project. Ship US1–US4 together as the first release.

### Incremental Delivery

| Increment | Stories | State |
|---|---|---|
| 1 | Foundational + US1 | Demoable — creation works |
| 2 | + US2 | Honest display; no misleading zeroes |
| 3 | + US3 | Expense-ledger mode complete |
| 4 | + US4 | **Shippable** — no false alarms |
| 5 | + US5 | Full lifecycle, invariant closed |
| 6 | + US6 + Polish | Complete |

### Risk Notes

- **T007 is the hinge.** It intentionally breaks the build in 27 files. Work through the analyzer output; resist `?? 0`.
- **T053 must bypass both arms** of the risk rule. Patching only the contract comparison leaves every expense-ledger project flagged "losing".
- **T054 touches one `remainingBalance` of two.** The accounting-summary one is a different formula; changing it corrupts supplier and client balances.
- **T075 must not go through PowerShell.** Arabic strings corrupt, and the localization fallback is silent — English would quietly ship to Arabic users.

---

## Summary

| Phase | Story | Tasks | Count |
|---|---|---|---|
| 1 | Setup | T001–T003 | 3 |
| 2 | Foundational | T004–T016, T085 | 14 |
| 3 | US1 (P1) | T017–T024 | 8 |
| 4 | US2 (P1) | T025–T034 | 10 |
| 5 | US3 (P1) | T035–T048, T083, T084 | 16 |
| 6 | US4 (P1) | T049–T056 | 8 |
| 7 | US5 (P2) | T057–T068 | 12 |
| 8 | US6 (P3) | T069–T073, T086 | 6 |
| 9 | Polish | T074–T082 | 9 |
| | **Total** | | **86** |

Test tasks: 29. Implementation tasks: 48. Setup/verification: 9.

**Task ID policy**: IDs are append-only. T083–T086 were added after the initial numbering, in response to the coverage gaps found by `/speckit-analyze`, and are listed inside the phase they belong to rather than at the end of the file. Renumbering 82 existing tasks to restore strict positional ordering would break every cross-reference in the analysis, the plan, and this file's dependency graph for no execution benefit. Execute by phase, not by ID order.
