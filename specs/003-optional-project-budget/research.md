# Phase 0 Research: Optional Project Budget

**Branch**: `003-optional-project-budget` | **Date**: 2026-08-17

All unknowns from Technical Context are resolved below. Each decision was verified against the
existing codebase rather than assumed, because this feature changes a field that eight production
files and eighteen test files already treat as non-nullable.

---

## R1. How to represent an absent Contract Value

**Decision**: `null`, exactly mirroring how `budgetLimit` already represents absence.

**Rationale**: `budgetLimit` is already the optional-money precedent in this codebase, and it is
implemented consistently at all four layers:

- Firestore rules: `budgetLimit == null || (budgetLimit is number && budgetLimit > 0)`
- Cloud Function: `Number(data.budgetLimit ?? 0) || null` — coerces `0` to `null`
- Dart model: `final double? budgetLimit`
- Parsing: `(map['budgetLimit'] as num?)?.toDouble()`

Copying this shape for `contractValue` means zero new patterns, and it satisfies FR-003 ("zero and
empty are equivalent") for free, since `Number(x) || null` already collapses `0` to `null`.

**Alternatives considered**:

- *Omit the field entirely when absent* — rejected. Firestore rules `hasOnly()` checks and the
  metrics merger both read fields by name; a missing key behaves differently from an explicit null
  in `diff().affectedKeys()`, which would complicate the update rule.
- *Sentinel `0` meaning absent* — rejected. It is the status quo failure mode: `0` is
  indistinguishable from a real zero and is exactly what produces today's misleading widgets.

---

## R2. Making `Project.contractValue` nullable in Dart

**Decision**: `final double? contractValue`, with `Project.fromMap` reading
`(map['contractValue'] as num?)?.toDouble()` and no `?? 0` fallback.

**Rationale**: The `?? 0` fallback is the single line that would silently defeat the whole feature —
it converts absence back into a fake zero at the model boundary, and every downstream widget would
then see `0` rather than `null`. Constitution principle II ("old records without newer fields MUST
load with deterministic fallback values") is still satisfied: every pre-existing project has a
contract value above zero, so no legacy record resolves to null by accident.

**Blast radius** (measured, not estimated): 9 lib files and 18 test files reference `contractValue`.
The compiler finds all of them once the type changes, which is the intended migration mechanism.

---

## R3. Single source of truth for the two switches

**Decision**: Add derived getters to the `Project` domain model — `hasContractValue`, `budgetBase`,
`hasBudget`, and `isExpenseLedger` — and route every widget through them.

**Rationale**: FR-009 requires that every surface agree on the budget determination. Today the
`budgetBase`/`hasBudget` derivation is **duplicated verbatim** in two files:

- `lib/features/projects/presentation/screens/project_detail_screen.dart:266-269`
- `lib/features/dashboard/presentation/screens/dashboard_screen.dart:394-397`

and a third, subtly different rule lives in `projects_screen.dart:701-703` (which gates on
`budgetLimit` only, ignoring `contractValue`). Three copies of a rule that must agree is precisely
the drift FR-009 exists to prevent. Consolidating is a prerequisite, not a nicety.

Definitions:

| Getter | Rule |
|---|---|
| `hasContractValue` | `contractValue != null && contractValue! > 0` |
| `budgetBase` | `budgetLimit` when `> 0`, else `contractValue`, else `null` |
| `hasBudget` | `budgetBase != null && budgetBase! > 0` |
| `isExpenseLedger` | `!hasContractValue` |

**Alternatives considered**: a separate presentation-layer helper class — rejected as a fourth place
for the rule to live. The rule is about the project's own state, so it belongs on the entity.

---

## R4. Where to enforce the contract-and-payment invariant

**Decision**: Enforce in the Cloud Functions layer (authoritative), and mirror it in the client for
fast feedback. Firestore rules are *not* used for the cross-document half of the invariant.

**Rationale**: Tracing the mutation path shows every write already funnels through callable
functions via the offline queue:

```
create/edit screen → repository → workspace_mutation_service._enqueueForBackgroundSync
                   → offline queue → callable Cloud Function → Firestore
```

That makes the callables the natural chokepoint, and it satisfies FR-041 (a queued offline edit
cannot bypass enforcement) without any new infrastructure.

Firestore rules are deliberately excluded from the cross-document check: validating "this project
has no payments" from a rule requires a `get()` per write, which bills an extra document read on
every payment and still cannot see the offline queue. Rules keep doing what they do well — shape
validation on the single document being written.

**Enforcement points**:

| Requirement | Location |
|---|---|
| FR-037 — reject payment on contract-less project | `createPaymentWithQuotaForUser` in `functions/src/index.ts` (and its HTTP twin) |
| FR-039 — block clearing contract while payments exist | `updateProject` callable in `functions/src/index.ts` |
| FR-038 — hide such projects from pickers | client-side filter in payment project selection |
| FR-039 client mirror | pre-save check in the project edit screen |

---

## R5. How to test "has any payment record"

**Decision**: Query `payments` filtered by `projectId` with `limit(1)`, plus a scan of the offline
queue for pending `createPayment` actions targeting that project.

**Rationale**: FR-039a requires *record existence*, not the payment total, so the check cannot read
`totalPayments` off the project metrics — a zero-amount or refunded payment leaves a record while
the total reads zero. A `limit(1)` existence probe is O(1) and respects constitution principle V
(no unbounded reads). The queue scan covers the edge case the spec calls out explicitly: a payment
still awaiting sync must block the clear.

**Index**: none required. `firestore.indexes.json` already carries `payments` composites keyed on
`projectId`, and an existence probe needs no new ordering.

---

## R6. Suppressing risk classification without a contract

**Decision**: In `recomputeProjectMetrics`, short-circuit before the risk block when
`contractValue == null`: write `riskLevel` and `healthStatus` as `null`, write `remainingBalance`
as `null`, and unconditionally clear any existing `project_risk_alert` notification.

**Rationale**: The current rule at `functions/src/index.ts:4330-4335` is

```ts
if (netProfit < 0 || expectedFinalCost > contractValue) { riskLevel = "high"; ... }
```

Both arms misfire without a contract. The contract arm compares against `0`; the net arm fires
because `netProfit = totalPayments − totalExpenses` is negative for any expense-only project. This
is why the clarified answer was full suppression — patching only the contract arm leaves every
expense-ledger project permanently flagged "losing".

Clearing the notification unconditionally satisfies FR-021 (a project whose contract is removed must
shed its stale alert). `budgetExceeded` is untouched: it already reads
`budgetLimit != null && totalExpenses > budgetLimit`, which is correct as written.

**Consumer safety check**: `riskLevel`/`healthStatus`/`remainingBalance` are written to the
`project_metrics` document and passed through `mergeProjectMetricsData`, but the Dart `Project`
model never reads them, and the dashboard warnings list keys off `budgetLimit` only. Nulling them is
therefore contained to the metrics document.

---

## R7. Terminology collision on `remainingBalance`

**Decision**: Only the project-metrics `remainingBalance` changes. The accounting-summary one is
left strictly alone.

**Rationale**: The name is overloaded across two unrelated calculations:

| Location | Formula | Meaning |
|---|---|---|
| `project_metrics` | `contractValue − totalPayments` | contract left to invoice — **contract-derived, must become null** |
| accounting summaries (`index.ts:1366,1405,1439`) | `totalExpenses − totalPayments` | per-supplier / per-client balance — **unrelated, must not change** |

Touching the second would corrupt supplier and client balances, a direct violation of constitution
principle II. FR-023 was amended during clarification to scope itself explicitly.

---

## R8. Localization file handling

**Decision**: Add new keys to both the `_en` and `_ar` maps in
`lib/app/localization/app_localizations.dart` using the `Edit` tool only. Never process this file
through PowerShell `Get-Content`/`Set-Content`.

**Rationale**: The file is a hand-rolled `Map<String, String>` pair containing Arabic text.
Round-tripping it through PowerShell's default encoding corrupts the UTF-8 Arabic strings. The
localization system falls back to English silently on a missing key, so a missed Arabic entry
produces no error — it just quietly ships English text to Arabic users, which FR-027 forbids.

**New keys required**: expense-ledger empty-state title and body, a set-contract-value action, and
two invariant-violation messages (payment blocked, contract clear blocked).

---

## R9. Test strategy

**Decision**: Extend the existing suites in place; add no new frameworks.

| Layer | Runner | Scope |
|---|---|---|
| Dart unit | `flutter test` | `Project` derived getters — the truth table for the two switches |
| Dart widget | `flutter test` | each adapted surface, both modes, plus Arabic/RTL |
| Functions | `npm test` (`node --test` over compiled JS) | risk suppression, both invariant guards |
| Rules | existing `firestore_rules.test.ts` | null contract accepted, negative still rejected |

Eighteen existing test files assert a non-null `contractValue`. Per constitution principle III these
are updated, never deleted — they are the regression net proving contract-bearing projects still
behave identically (FR-018).
