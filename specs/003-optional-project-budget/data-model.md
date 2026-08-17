# Phase 1 Data Model: Optional Project Budget

**Branch**: `003-optional-project-budget` | **Date**: 2026-08-17

---

## Entity: Project

**Collection**: `projects` | **Dart**: `lib/features/projects/domain/project.dart`

### Changed field

| Field | Before | After | Notes |
|---|---|---|---|
| `contractValue` | `double` (required, `> 0` enforced) | `double?` (optional, `> 0` when present) | `0` normalizes to `null` at every boundary |

### Unchanged fields

`id`, `workspaceId`, `name`, `clientName`, `status`, `completionPercentage`, `totalExpenses`,
`totalPayments`, `netProfit`, `isArchived`, `clientMutationId`, `location`, `description`,
`budgetLimit`, `startDate`, `expectedEndDate`.

`budgetLimit` is already `double?` and its semantics do not change.

### Derived getters (new — no storage)

These are the single source of truth required by FR-009 and FR-014. They replace the three
divergent copies of this logic currently living in `project_detail_screen.dart`,
`dashboard_screen.dart`, and `projects_screen.dart`.

| Getter | Type | Rule | Governs |
|---|---|---|---|
| `hasContractValue` | `bool` | `contractValue != null && contractValue! > 0` | contract displays, risk eligibility |
| `budgetBase` | `double?` | `budgetLimit` when `> 0`, else `contractValue`, else `null` | which amount spend is measured against |
| `hasBudget` | `bool` | `budgetBase != null && budgetBase! > 0` | budget-usage widgets |
| `isExpenseLedger` | `bool` | `!hasContractValue` | revenue-side widgets |

### The two switches

`hasBudget` and `isExpenseLedger` are **independent**. All four combinations are valid and reachable:

| `contractValue` | `budgetLimit` | Budget widgets | Revenue side | Interpretation |
|---|---|---|---|---|
| set | set | yes (vs. limit) | yes | today's fully-specified project |
| set | absent | yes (vs. contract) | yes | today's default — **must be unchanged** (FR-018) |
| absent | set | yes (vs. limit) | no | spending budget, no income expected |
| absent | absent | no | no | pure expense ledger |

### Validation rules

| Rule | Enforced at | Requirement |
|---|---|---|
| `contractValue` null, or a number `> 0` | Firestore rules, Cloud Function, client form | FR-001, FR-004, FR-007 |
| `0` is stored as `null` | Cloud Function coercion, client parse | FR-003 |
| Negative rejected | client form, Cloud Function | FR-004 |
| Cannot be cleared while a payment record exists | `updateProject` callable + client pre-check | FR-039, FR-039a, FR-041 |

### State transitions

```
                    set Contract Value
   [expense-ledger] ────────────────────> [contract-bearing]
        ▲                                        │
        │      clear Contract Value              │
        └──────── (blocked if any ───────────────┘
                   payment record exists)
```

Entering the contract-bearing state restores budget widgets, revenue widgets, and risk eligibility
in one step (FR-034, US5-S1). Leaving it is gated by the invariant (FR-039).

`budgetLimit` transitions freely in both directions at any time, independent of payments (FR-005, and the "Budget Limit is unconstrained" assumption).

---

## Entity: Payment

**Collection**: `payments`

No schema change. One new referential rule:

> A payment record may only exist against a project that has a Contract Value.

| Rule | Enforced at | Requirement |
|---|---|---|
| Reject payment creation on a contract-less project | `createPaymentWithQuotaForUser` + HTTP variant | FR-037, FR-041 |
| Exclude contract-less projects from payment pickers | client-side filter | FR-038 |

"Has payments" for the purposes of the invariant means **a payment record exists**, established by a
`limit(1)` existence probe plus a scan of pending offline `createPayment` actions. It explicitly
does **not** mean `totalPayments > 0` — a zero-amount or refunded payment still blocks (FR-039a).

---

## Entity: Project Metrics

**Collection**: `project_metrics` | Written by `recomputeProjectMetrics` in `functions/src/index.ts`

### Changed fields

| Field | Before | After | Requirement |
|---|---|---|---|
| `contractValue` | `number` | `number \| null` | mirrors the project |
| `remainingBalance` | `number` (`contract − payments`) | `number \| null` — null when no contract | FR-023 |
| `riskLevel` | `"low" \| "medium" \| "high"` | same `\| null` — null when no contract | FR-019 |
| `healthStatus` | `"healthy" \| "warning" \| "losing"` | same `\| null` — null when no contract | FR-019 |

### Unchanged fields

`budgetLimit`, `budgetExceeded`, `totalExpenses`, `totalLaborCost`, `totalPayments`, `netProfit`,
`expectedFinalCost`, `categoryTotals`, `entityTotals`, `paymentMethodTotals`, `weeklyExpenses`,
`weeklyIncome`, `equipmentExpenses`, `recentTransactions`, `monthlyFlow`, `topWorkers`,
`recentExpenses`, `recentPayments`.

`budgetExceeded` already reads `budgetLimit != null && totalExpenses > budgetLimit` and is correct
as written — it must not be modified.

### Consumer safety

`mergeProjectMetricsData` copies these fields through by name, and the Dart `Project` model does not
read `riskLevel`, `healthStatus`, or `remainingBalance`. The dashboard warnings list keys off
`budgetLimit` only. Nulling these three fields is therefore contained to the metrics document and
its direct readers.

---

## Not an entity change: accounting summaries

`AccountingSummary.remainingBalance` (`lib/core/models/accounting_summary.dart`) is a **different
quantity** with the same name: `totalExpenses − totalPayments` for a supplier, client, or worker.

It is unrelated to the contract and **must not be touched**. Changing it would corrupt supplier and
client balances (constitution principle II). See research R7.
