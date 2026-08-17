# Implementation Plan: Optional Project Budget

**Branch**: `003-optional-project-budget` | **Date**: 2026-08-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-optional-project-budget/spec.md`

## Summary

Make a project's Contract Value optional so a project can be created purely to record expenses, and
make every budget-derived surface adapt rather than display zeroes or fire false alarms.

The technical approach has three parts:

1. **Nullable field, existing pattern.** `contractValue` becomes `double?` / `number | null`,
   mirroring exactly how `budgetLimit` already models an optional money value at all four layers
   (rules, callable, model, parser). No new pattern is introduced.
2. **Two independent switches, derived once.** `hasBudget` governs budget-usage widgets;
   `isExpenseLedger` governs the revenue side. Both become getters on `Project`, replacing three
   divergent copies of this logic that exist in the codebase today.
3. **An enforced invariant.** A project with no Contract Value cannot hold payments. Enforced in the
   callable Cloud Functions (authoritative, and the only layer that sees offline-queued writes),
   mirrored in the client for fast feedback.

The riskiest part is not the UI. It is that `contractValue` is currently required by Firestore rules,
by two Cloud Functions, and by a non-nullable Dart field, and that the risk-classification rule
misfires on **both** of its arms when the contract is absent.

## Technical Context

**Language/Version**: Dart 3 / Flutter (mobile app); TypeScript on Node (Cloud Functions)

**Primary Dependencies**: Flutter, Riverpod, Firebase (Firestore, Auth, Functions, Storage), intl

**Storage**: Cloud Firestore — `projects`, `payments`, `expenses`, `project_metrics`,
`accounting_summaries`, `notifications`; plus a local offline action queue

**Testing**: `flutter test` (unit + widget, ~18 existing files touch this field); `npm test` in
`functions/` (`tsc` then `node --test` over compiled `lib/`); Firestore rules tests in
`functions/src/firestore_rules.test.ts`

**Target Platform**: Android and iOS, mobile-first, field use with intermittent connectivity

**Project Type**: Mobile app + serverless backend

**Performance Goals**: No new unbounded reads. The one new query is a `limit(1)` existence probe,
run only when a user clears a Contract Value.

**Constraints**: Must work offline with recoverable, idempotent sync; financial figures gated by the
existing role model; Arabic/RTL parity required; no new Firestore indexes (existing `payments`
composites already cover the probe)

**Scale/Scope**: 9 lib files and 18 test files reference `contractValue`; 6 UI surfaces render
budget-derived content; 3 backend enforcement points

**Unknowns**: None. All resolved in [research.md](./research.md).

## Constitution Check

*GATE: evaluated before Phase 0 and re-evaluated after Phase 1 design.*

### I. Preserve Existing Product Behavior — PASS

The change is additive: `contractValue` gains a null case. Every existing project has a value above
zero, so no existing project's behaviour changes. FR-018 states this as a requirement, SC-004
measures it, and manual check M8 plus the 18 updated test files enforce it. Those tests are updated
rather than deleted, per principle III — they are the regression net.

*Post-Phase-1 re-check*: still passing. The design adds nullable branches and consolidates three
duplicate derivations; it replaces no working system.

### II. Accounting Correctness and Traceability — PASS

- No silent data loss: the invariant makes "payments with no contract" unreachable, so no payment is
  ever hidden. A blocked save leaves all data untouched (FR-040).
- No ambiguous financial state: `0` and absent are collapsed to one representation (FR-003), which
  removes today's real ambiguity where a placeholder zero is indistinguishable from a real amount.
- Deterministic fallback for old records: pre-existing projects all carry a positive
  `contractValue`, so none resolves to null by accident.
- **Traceability risk identified and contained**: `remainingBalance` is an overloaded name. The
  contract-derived one in `project_metrics` becomes nullable; the per-supplier/per-client one in
  accounting summaries is a different formula and must not be touched. FR-023 was amended during
  clarification to scope itself, and research R7 records the distinction.

### III. Test-Backed Change Discipline — PASS

This change is high-risk on three of the named axes (accounting, offline, permissions-adjacent), so
tests are mandatory, not optional. Coverage spans unit, widget, Cloud Functions, and rules layers
(see quickstart.md). Two paths cannot be reliably automated — notification delivery and offline sync
— and both have documented manual procedures (M6, M7).

### IV. Offline, Security, and Recovery First — PASS

- Enforcement lives in the callables, the only layer that sees offline-queued writes; rules alone
  would be bypassable by a queued edit (FR-041).
- A rejected queued action must surface to the user rather than retry silently — called out as an
  edge case ("two offline edits racing") and in contract C5.
- Optimistic placeholders must carry a null contract, not `?? 0` (FR-008).
- The existing financial-access role model is untouched; FR-028 forbids the budget-less state from
  becoming a route to restricted figures.

### V. Scalable Data Access — PASS

One new query: a `limit(1)` existence probe on `payments`, run only when a user clears a Contract
Value. No new indexes — `firestore.indexes.json` already carries `payments` composites keyed on
`projectId`. The payment-picker filter (FR-038) runs client-side over an already-loaded, paginated
list, adding no reads.

**Gate result: PASS on all five principles, before and after design. No violations to justify, so
Complexity Tracking is omitted.**

## Project Structure

### Documentation (this feature)

```text
specs/003-optional-project-budget/
├── plan.md                          # This file
├── spec.md                          # Feature specification (4 clarifications recorded)
├── research.md                      # Phase 0 — 9 resolved decisions
├── data-model.md                    # Phase 1 — entities, switches, transitions
├── quickstart.md                    # Phase 1 — automated + manual verification
├── contracts/
│   └── mutation-contracts.md        # Phase 1 — callables, rules, queue, derived contract
├── checklists/
│   └── requirements.md              # Spec quality checklist (16/16)
└── tasks.md                         # Phase 2 — created by /speckit-tasks, NOT by this command
```

### Source Code (repository root)

```text
lib/
├── features/projects/
│   ├── domain/project.dart                              # nullable field + 4 derived getters
│   ├── data/project_repository.dart                     # nullable params; optimistic placeholder
│   └── presentation/
│       ├── screens/create_project_screen.dart           # optional field, invariant pre-check
│       ├── screens/project_detail_screen.dart           # budget card, contract row, revenue side
│       ├── screens/projects_screen.dart                 # card: budget bar, profit/loss row
│       └── widgets/project_details_widgets.dart         # FinancialGrid, ActionGrid
├── features/dashboard/presentation/screens/dashboard_screen.dart   # project-scoped section
├── features/payments/presentation/screens/add_payment_screen.dart  # picker filter
├── core/services/workspace_mutation_service.dart        # nullable queue payloads
└── app/localization/app_localizations.dart              # new _en + _ar keys (Edit tool only)

functions/src/
└── index.ts                                             # createProject, updateProject,
                                                         # createPaymentWithQuotaForUser,
                                                         # recomputeProjectMetrics

firestore.rules                                          # contractValue null-or-positive

test/                                                    # 18 files reference contractValue
├── widget/                                              # detail, dashboard, projects, RTL, dark
├── features/projects/data/project_repository_test.dart
└── domain/

functions/src/
├── firestore_rules.test.ts
└── project_recompute_trigger.test.ts
```

**Structure Decision**: Existing Flutter feature-first layout under `lib/features/<feature>/
{domain,data,presentation}` with shared code in `lib/core`, plus a single-file Cloud Functions
backend in `functions/src/index.ts`. No new directories. The feature touches existing files
exclusively, which is what principle I asks for.

## Implementation Sequencing

Ordered by dependency. Later groups do not compile or cannot be verified until earlier ones land.

| # | Group | Why it comes here |
|---|---|---|
| 1 | Firestore rules — accept null contract | Gates everything. Until rules accept it, no null-contract project can be written, so nothing downstream is testable end to end. |
| 2 | Cloud Functions — create/update accept null; risk suppression | Server must accept and correctly recompute before the client can produce the state. |
| 3 | Domain model — nullable field + 4 derived getters | The compiler-driven migration. Changing the type surfaces every one of the 9 lib and 18 test call sites. |
| 4 | Data + queue layer — nullable params, optimistic placeholder | Sits between the model and every screen. |
| 5 | Create/edit screen — optional field, normalization | Delivers US1, the first independently shippable slice. |
| 6 | UI adaptation — 6 surfaces via the derived getters | Delivers US2 and US3. Depends on group 3's getters existing. |
| 7 | Invariant enforcement — callables, picker filter, pre-check | Delivers the clarified rule. Depends on groups 2 and 5. |
| 8 | Empty-state + localization (en + ar) | Delivers FR-016. Depends on group 6's layout. |
| 9 | Reports | Delivers US6, the P3 slice. |
| 10 | Test updates across all 18 files, plus new cases | Continuous with each group, not a trailing phase — principle III. |

Groups 1–6 constitute the minimum viable slice: a user can create a budget-less project and see it
render honestly. Group 7 closes the invariant. Groups 8–9 complete the experience.

## Risks

| Risk | Mitigation |
|---|---|
| `?? 0` fallback reintroduced anywhere on the parse path silently defeats the whole feature | Explicit contract test: a stored `0` must load as `null` (quickstart, unit case 2) |
| Touching the wrong `remainingBalance` corrupts supplier/client balances | Research R7 and data-model both name the two formulas and their files; FR-023 is scoped |
| Patching only the contract arm of the risk rule leaves every expense-ledger project "losing" | Research R6 documents both arms; functions test asserts null risk, not low risk |
| PowerShell round-trip corrupts Arabic localization strings | Documented in research R8 and quickstart; use the Edit tool on that file only |
| Three existing copies of the budget derivation drift further apart | Group 3 consolidates them into `Project` getters before group 6 consumes them |
| A queued offline clear that violates the invariant retries forever | Contract C5 requires the rejection to surface to the user |

## Phase Status

- [x] Phase 0 — research complete, 9 decisions recorded, no unresolved unknowns
- [x] Phase 1 — data model, contracts, and quickstart generated; agent context updated
- [x] Constitution check — PASS before Phase 0 and after Phase 1
- [ ] Phase 2 — task breakdown (run `/speckit-tasks`)
