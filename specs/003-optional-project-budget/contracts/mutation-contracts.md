# Phase 1 Contracts: Optional Project Budget

**Branch**: `003-optional-project-budget` | **Date**: 2026-08-17

The app's external interfaces are its callable Cloud Functions and its Firestore security rules.
Both are contracts between the Flutter client (including its offline queue) and the backend.

---

## C1. `createProject` — callable

**Change**: `contractValue` moves from required to optional.

| Aspect | Before | After |
|---|---|---|
| Parse | `requireNumber(data, "contractValue")` | `Number(data.contractValue ?? 0) \|\| null` |
| Missing value | `HttpsError("invalid-argument")` | accepted, stored as `null` |
| Zero | accepted, stored as `0` | stored as `null` |
| Negative | accepted (rules rejected later) | rejected with `invalid-argument` |

**Contract tests**:

| # | Given | Expect |
|---|---|---|
| 1 | payload with no `contractValue` | 201-equivalent success, document has `contractValue: null` |
| 2 | payload with `contractValue: 0` | success, stored as `null` |
| 3 | payload with `contractValue: -5` | rejected, `invalid-argument` |
| 4 | payload with `contractValue: 50000` | success, stored as `50000` — unchanged behaviour |

---

## C2. `updateProject` — callable

**Change**: accepts a null `contractValue`, but enforces the invariant (FR-039, FR-041).

| Aspect | Before | After |
|---|---|---|
| Parse | `requireNumber(data, "contractValue")` | `Number(data.contractValue ?? 0) \|\| null` |
| Clearing with payments | n/a | **rejected** — `failed-precondition` |
| Clearing without payments | n/a | accepted, stored as `null` |

**Precondition check**: before writing, when the incoming `contractValue` is null and the stored one
is not, probe `payments` for `projectId == <id>` with `limit(1)`. A hit rejects the write.

**Contract tests**:

| # | Given | Expect |
|---|---|---|
| 1 | project with contract, no payments, clear it | success, `contractValue: null` |
| 2 | project with contract and ≥1 payment, clear it | rejected `failed-precondition`, **project unchanged** (FR-040) |
| 3 | project with contract and one zero-amount payment, clear it | rejected — record existence, not total (FR-039a) |
| 4 | contract-less project, set a contract | success |
| 5 | project with payments, edit name only (contract untouched) | success — the guard fires only on a clear |

---

## C3. `createPaymentWithQuotaForUser` — callable (and HTTP twin)

**Change**: rejects payments against contract-less projects (FR-037, FR-041).

**Precondition check**: load the target project; when `contractValue` is null or absent, reject
before any quota consumption or write.

**Contract tests**:

| # | Given | Expect |
|---|---|---|
| 1 | payment against a contract-bearing project | success — unchanged behaviour |
| 2 | payment against a contract-less project | rejected `failed-precondition`, no document written, no quota consumed |
| 3 | payment against a missing project | existing not-found behaviour, unchanged |

Both the callable and the `onRequest` HTTP variant share `createPaymentWithQuotaForUser`, so the
guard placed there covers both entry points.

---

## C4. Firestore security rules

**File**: `firestore.rules`

**Change**: `contractValue` validation adopts the shape `budgetLimit` already uses.

```
# before
&& request.resource.data.contractValue is number
&& request.resource.data.contractValue > 0

# after
&& (
     request.resource.data.contractValue == null
     || (
          request.resource.data.contractValue is number
          && request.resource.data.contractValue > 0
        )
   )
```

`contractValue` stays in the update rule's `affectedKeys().hasOnly([...])` list — unchanged.

The cross-document invariant is **deliberately not** enforced here. Doing so would require a `get()`
per payment write, billing an extra read on every payment, and rules cannot see the offline queue
anyway. See research R4.

**Contract tests** (extend `functions/src/firestore_rules.test.ts`):

| # | Given | Expect |
|---|---|---|
| 1 | project create with `contractValue: null` | allowed |
| 2 | project create with `contractValue: 50000` | allowed — unchanged |
| 3 | project create with `contractValue: 0` | denied (client normalizes to null before writing) |
| 4 | project create with `contractValue: -1` | denied |
| 5 | project update setting `contractValue: null` | allowed at the rules layer — invariant is the callable's job |

---

## C5. Offline queue payloads

**File**: `lib/core/services/workspace_mutation_service.dart`

`createProject` and `updateProject` signatures change from `required double contractValue` to
`double? contractValue`. The payload carries `null` rather than omitting the key, so the Cloud
Function's `?? 0 || null` coercion sees an explicit null.

**Behavioural requirements**:

- A queued create with a null contract syncs successfully (FR-008).
- A queued clear that violates the invariant surfaces the rejection to the user rather than failing
  silently, and the queued action does not retry forever (FR-041, edge case "two offline edits
  racing").
- The optimistic placeholder project built from a queued action must carry `contractValue: null`,
  not `?? 0` (FR-008, US1-S3). This is the line at `project_repository.dart:1062`.

---

## C6. Client-side derived contract

Not an external interface, but the contract every widget depends on. Defined once on `Project`
(see data-model.md) and consumed everywhere:

| Consumer | Reads |
|---|---|
| project detail budget card | `hasBudget`, `budgetBase` |
| project detail contract row / metric card | `hasContractValue` |
| project detail revenue widgets + empty-state | `isExpenseLedger` |
| dashboard project section | `hasBudget`, `budgetBase`, `hasContractValue`, `isExpenseLedger` |
| project list card | `hasBudget`, `budgetBase`, `isExpenseLedger` |
| payment project picker | `hasContractValue` |

No consumer may re-derive these rules locally. That duplication is what this contract exists to
eliminate (FR-009).
