# Specification Quality Checklist: Optional Project Budget

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-17
**Last validated**: 2026-08-17 (post-analyze remediation)
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Validation iteration 3: all items pass, after four clarifications recorded in the spec's
  Clarifications section (session 2026-08-17).
- The clarification pass materially changed the feature's shape. Expense-ledger mode was
  originally gated on "no budget and no payments"; it is now gated on Contract Value alone,
  backed by a new enforced invariant — a project with no Contract Value cannot hold payments.
  That converted a presentation rule into a data rule, adding FR-037 through FR-042.
- Two switches are now explicitly independent: the budget baseline governs budget-usage widgets,
  the Contract Value governs the revenue side. A Budget-Limit-only project shows spending progress
  with no revenue side, which is intended rather than incidental.
- Risk classification is fully suppressed without a Contract Value. Both arms of the existing rule
  had to go — the negative-net arm alone would have flagged every expense-only project as losing.
- Vague wording in FR-029 was tightened without spending a question, since it had one defensible
  answer rather than a genuine choice.
- Facts verified against the codebase rather than assumed: `remainingBalance` is overloaded across
  project metrics and accounting summaries (FR-023 now scopes itself to the contract-derived one);
  the add-payment flow currently accepts any project (FR-038 constrains it); the project list card
  renders profit/loss wording today (FR-033 is a real change).

### Post-analyze remediation (2026-08-17)

`/speckit-analyze` raised 13 findings; all were fixed. The two that mattered:

- **FR-013 contradicted FR-031.** FR-013 required income, net, and profit margin to keep rendering
  for budget-less projects; FR-031 required them hidden in expense-ledger mode. Since a budget-less
  project always lacks a Contract Value, both governed the same projects with opposite instructions.
  FR-013 is now scoped to expense totals, with revenue-side behaviour delegated to FR-031. US2-S8
  had the same defect and was split into two scenarios.
- **Out of Scope contradicted FR-037/FR-038.** It excluded "any change to how payments are
  recorded" while the invariant adds a precondition to exactly that. The exclusion now names the
  one precondition explicitly.

Both traced to the same cause: the clarification session moved expense-ledger mode from a
payments-gated rule to a Contract-Value-gated one, and three passages written beforehand were not
revisited.

Also fixed: three zero-coverage requirements gained tasks (FR-035 → T083/T086, FR-024 → T085,
FR-016 test → T084); FR-006 coverage extended in T058; FR-017/FR-036 and FR-014/FR-030 merged to
remove duplication; requirement blocks reordered into ascending numeric order; "budget-less"
replaced with "no Contract Value" wherever risk or reports were meant.

US6 shrank in truth rather than in scope: report output never displayed Contract Value or Budget
Limit, so the "omit contract lines" test would have passed vacuously. That phase now targets the
revenue sections and workspace aggregates, against named files.

### Implementation verification (2026-08-17)

59 of 86 tasks complete. All four P1 stories are implemented end to end; US5 client-side and the
US6 project reports are done. Verification at this point:

- `flutter analyze` — no issues
- `flutter test` — **596 passed**, 0 failed (571 pre-change baseline + 25 new)
- `functions npm test` — 38 tests, **35 passed, 0 failed, 3 skipped**

The 3 skips are emulator-gated (Firestore rules, project-recompute trigger, storage rules) and
require `FIRESTORE_EMULATOR_HOST`. Consequence worth stating plainly: the rules change and the
notification side of risk suppression are verified by compilation and review only. The risk
*rule itself* was extracted into an exported `classifyProjectRisk` so its 7 cases run without an
emulator — it is the highest-consequence branch, since a wrong verdict notifies every member with
risk alerts enabled.

Two defects were found by the new tests rather than by inspection:

- `Project.fromMap` passed a stored `0` through as `0.0`, violating FR-003. Fixed at the model
  boundary so no consumer has to know about the zero case.
- Invariant rejections would have been categorised as `quota` by `SyncErrorClassifier`, telling
  the user they hit a plan limit. They now map to `invalidTarget`.

### Backend verification closed (2026-08-17, third pass)

67 of 86 tasks complete. The emulator gap identified in the previous pass is **closed**: the
Firebase CLI and a JVM were both available, so `firebase emulators:exec --only firestore` runs the
previously-skipped suites. The command is now recorded in quickstart.md, since plain `npm test`
silently skips the majority of this feature's backend coverage.

- `flutter analyze` — no issues
- `flutter test` — **596 passed**, 0 failed
- `firebase emulators:exec ... npm test` — **111 tests, 110 passed, 0 failed, 1 skipped**

The single remaining skip is the storage-rules suite, which needs
`FIREBASE_STORAGE_EMULATOR_HOST` and is unrelated to this feature.

Backend coverage added and **executed** against the emulator: the relaxed rules (null accepted,
zero and negative still denied, contract settable on a contract-less project), createProject's four
contract cases, the updateProject invariant including the zero-amount-payment case and the
project-unchanged assertion, payment refusal on contract-less projects, and risk suppression with
its notification behaviour.

To make the invariant testable, `updateProject`'s body was split into an exported
`updateProjectForUser` and `createProjectWithQuotaForUser` was exported. This follows the pattern
the file already used for the expense and payment creators, which exist in exactly that shape for
the same reason.

### Frontend coverage closed (2026-08-17, fourth pass)

75 of 86 tasks complete.

- `flutter analyze` — no issues
- `flutter test` — **599 passed**, 0 failed
- `firebase emulators:exec ... npm test` — 111 tests, 110 passed, 0 failed, 1 skipped

Added: the project-scoped dashboard in expense-ledger mode, the contract-restoration transition
(asserting budget progress resumes at 75% against pre-existing expenses rather than restarting at
0%), and report revenue omission.

**T073 was verified as a no-op rather than implemented.** FR-025 asks that contract-less projects be
excluded from budget-based workspace averages and ratios — but no such aggregate exists.
`reports_providers.dart` contains no budget or contract arithmetic at all, and the one
workspace-level budget aggregate (the dashboard over-budget warnings list) already keys on
`budgetLimit != null && > 0`, which was correct before this feature and stays correct. A
contract-less project with a Budget Limit still appears there, which is intended per FR-022.
This is the same class of finding as the vacuous US6 contract-lines test caught during analysis.

The report test asserts by document size rather than rendered text: PDF bytes are compressed, so
the established pattern in that suite is header + length. Dropping two table rows must make the
contract-less document strictly smaller; identical lengths would mean the rows were still emitted.

### Audit and remediation (2026-08-17, fifth pass)

A self-audit of the invariant found two defects that a fully green suite had not caught, plus
three lesser findings. All are fixed or recorded.

**A (HIGH, fixed)** — `updatePayment` can reassign `projectId`, so guarding only `createPayment`
left the invariant breachable from the far side: create a payment on a contract-bearing project,
then edit it onto a contract-less one. Now guarded, with the precondition extracted into a shared
`hasContractValue()` used by all three enforcing callables.

**C (HIGH, fixed)** — payments carry `allow create, delete: if false`, so archiving is the only
removal this app offers, and neither probe filtered `isArchived`. Once a project had ever taken a
payment its contract could never be cleared, while the refusal message told the user to remove the
payments. FR-042 was unsatisfiable as built. Both probes now exclude archived payments, so
archiving genuinely unblocks.

**B (LOW, fixed)** — rules permitted a direct client write clearing `contractValue`, bypassing the
callable that enforces the invariant. Closed without any extra read: the non-null-to-null
transition is now refused at the rules layer outright. The callable uses the admin SDK and is
unaffected, so the legitimate path still works. Setting or changing a value is still permitted.

**D (LOW, fixed)** — `FinancialGrid` rendered a lone card at half width in a two-column grid.
Single-card case now lays out on its own.

**E (recorded, not fixed)** — `FinancialGrid` is **dead code**: zero references in `lib` or `test`,
while `ActionGrid` and `ProjectTimeline` from the same file are both used. T033 and T045 therefore
had no user-visible effect, and FR-011's "project detail metric card" clause names a surface that
does not render. The real contract displays are the project-detail row and the dashboard row, both
of which are correctly gated. The widget was left in place — deleting it is a separate decision.

Four regression tests were added for A, B and C specifically because the originals passed while
both defects were live: the tests only exercised paths that had been designed for, not the ones
overlooked.

Verification after remediation:

- `flutter analyze` — no issues
- `flutter test` — **599 passed**, 0 failed
- `firebase emulators:exec ... npm test` — **114 tests, 113 passed, 0 failed, 1 skipped**

### Final automated coverage (2026-08-17, sixth pass)

83 of 86 tasks complete. Only three remain, all requiring a running app on a device: the visual
layout-artefact audit (T034), the manual quickstart walkthrough (T080), and the final sign-off
that depends on it (T082).

- `flutter analyze` — no issues
- `flutter test` — **605 passed**, 0 failed
- `firebase emulators:exec ... npm test` — 114 tests, 113 passed, 0 failed, 1 skipped

Added: offline-queue coverage (an optimistic contract-less create shows no fabricated zero; the
payment probe correctly ignores archived payments, sees active and queued ones, and is scoped to
the right project), and an Arabic/RTL render of the empty-state.

Two further requirements were **verified by inspection rather than implemented**, for the same
reason T073 was:

- **T070 / FR-025 (workspace aggregates)** — the portfolio rollup queries `expenses` and
  `payments` by `workspaceId` and never reads project documents, so a contract-less project's
  rows are included in absolute totals by construction. There is no budget-based average or ratio
  anywhere to exclude them from.
- **T068 / FR-028 (permissions)** — the expense-ledger branch on the project card sits inside the
  existing `_canAccessFinancial` gate, so the new state exposes nothing that was previously
  restricted. The project detail screen has no role gate, but that is pre-existing and unchanged
  by this feature.

One spec conflict surfaced and was resolved in favour of preserving behaviour: FR-009 asks every
surface to use the shared budget baseline, but the project list card has always required an
explicit Budget Limit. Using the baseline there would give contract-only projects a budget bar
they never had, breaking FR-018 and SC-004. A narrower `hasBudgetLimit` getter keeps the rule on
the model while preserving the card. **FR-009 should be amended to say surfaces must agree on the
determination, not that they must all render the same widgets.**
