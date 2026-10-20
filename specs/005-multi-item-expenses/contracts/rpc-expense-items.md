# Contract: Expense RPCs with Items

**Transport**: unchanged from 004 (`POST /v1/rpc/{name}`, Firebase ID token, App Check,
`X-Idempotency-Key` on mutating calls; see `specs/004-vps-backend-migration/contracts/rpc-api.md`).

All changes are **additive**. A payload without the new fields behaves exactly as today, so offline
queue entries created by the previous app build still replay (research R3).

---

## 1. `createExpenseWithQuota` (changed)

### Request: new or changed fields

| Field | Type | Required | Rule |
|---|---|---|---|
| `items` | `ExpenseItemInput[]` | no | 1–100 elements when present. See data-model §2. |
| `amount` | number | **yes if `items` absent**; optional if present | If both are sent, `amount` must equal Σ items (piastres). If only `items` is sent, the server sets `amount = Σ items`. |
| `description` | string | no | The expense **title**. Trimmed, with no server length cap (unchanged, so long notes-as-description payloads from old builds still replay). The app limits the title field to 200 chars. |
| `inputMethod` | string | no | `manual` (default) \| `voice` \| **`text`**. |
| `transcript` | string | no | Voice transcript or pasted text, ≤ 4,000 chars. |
| `source` | string | no | `rules` \| `llm` \| `hybrid`, otherwise stored as `''`. |

`ExpenseItemInput = { id?: string, name: string, amount: number, quantity?: number|null, note?: string }`

### Behavior
1. Existing checks run in the existing order (role, project, category, idempotency replay, quota).
2. If `items` is present, the server validates every item (data-model §2), generates missing `id`s,
   rejects duplicate `id`s, and computes the total. On `amount` mismatch it throws `invalid-argument`
   `"Amount must equal the sum of items"`.
3. If `items` is absent, it validates `amount > 0` as today and stores `items = []` (legacy shape).
   Old queued payloads don't change shape.
4. INSERT writes `items` and `amount` in the same statement. `recomputeProject` runs as today. The quota
   is consumed **once**.

### Response
Unchanged: `{ id: string, clientMutationId: string }`.

### Errors (new)
| Code | Message | When |
|---|---|---|
| `invalid-argument` | `Expense must have between 1 and 100 items` | `items` is `[]` or has > 100 elements |
| `invalid-argument` | `Item {i}: name is required` | Empty name after trim |
| `invalid-argument` | `Item {i}: name is too long` | Name > 120 chars |
| `invalid-argument` | `Item {i}: amount must be greater than zero` | ≤ 0 or non-numeric |
| `invalid-argument` | `Item {i}: amount can have at most 2 decimal places` | > 2 dp |
| `invalid-argument` | `Item {i}: quantity must be greater than zero` | quantity present and ≤ 0 or non-numeric (or > 2 dp: `…quantity can have at most 2 decimal places`) |
| `invalid-argument` | `Item {i}: note is too long` | Note > 200 chars |
| `invalid-argument` | `Item {i}: invalid id` / `Item {i}: duplicate id` | id fails `^[A-Za-z0-9_-]{6,36}$`, or repeats |
| `invalid-argument` | `Amount must equal the sum of items` | Total mismatch |
| `invalid-argument` | `inputMethod must be manual, voice or text` | Replaces the old message |

## 2. `updateExpense` (changed)

### Request: new or changed fields
Same `items` / `amount` rules as create. Also:
- `description`: **now persisted** (it was ignored before; research R4). Absent or `null` → unchanged.
  The client never substitutes `notes` for a missing description on update.
- `items` present → replaces the whole array, and `amount = Σ items`.
- `items` absent (legacy payload, for example an offline edit queued by the previous app build). The
  server looks at the **stored** row (`SELECT … FOR UPDATE`):

  | Stored `items` | Behavior |
  |---|---|
  | `[]` (legacy expense) | As today: `amount` from the payload, `items` stays `[]` |
  | exactly 1 item | `amount` from the payload, **and** that item's `amount` is rewritten to match (name, id, quantity and note are kept). The CHECK stays satisfied, and the old queued edit succeeds. |
  | 2 or more items | Rejected with `failed-precondition` (see errors). The offline queue shows it as a failed action, and the user re-edits on the new screen. |

Archived expense → `failed-precondition` (unchanged). Both old and new projects are recomputed when
the project changes (unchanged).

### Errors (new)
| Code | Message | When |
|---|---|---|
| `failed-precondition` | `This expense has several items; edit its items to change the amount` | `items` absent, `amount` sent, and the stored row has ≥ 2 items |
| `invalid-argument` | (same item messages as create) | `items` present and invalid |

The Postgres CHECK `expenses_amount_matches_items` (SQLSTATE `23514`) can only fire on a server bug,
because the paths above always keep it satisfied. If it fires, it is mapped to `internal` and logged.
It is never shown as a user error.

### Response
Unchanged: `null`.

## 3. `organizeExpenseText` (new)

Turns pasted receipt text into an AI Proposal. No records are written.

| Property | Value |
|---|---|
| Mutating | `true`. Requires `X-Idempotency-Key`, and a retry returns the first result without a second AI call. |
| Timeout | 60 s |
| Authorization | `assertCanMutateMoney(workspaceId)` |
| Offline queue | **Never queued.** The client calls it online only. |

### Request
```json
{
  "workspaceId": "ws_123",
  "text": "فاتورة سباكه شهر 10\n100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة",
  "currency": "EGP",
  "today": "2026-10-19",
  "languageHint": "ar"
}
```
| Field | Rule |
|---|---|
| `workspaceId` | Required. Projects and entities are loaded from **this** workspace. (Voice uses the profile's active workspace. This one is explicit.) |
| `text` | Required. 1–4,000 chars after trim. |
| `currency` | Optional default currency. Otherwise `EGP`. |
| `today` | Optional `YYYY-MM-DD` from the device, for relative dates. Otherwise the server date (Africa/Cairo). |
| `languageHint` | Optional, same parsing as voice. |

### Response
`ExpenseProposalResponse`:
```json
{
  "text": "فاتورة سباكه شهر 10\n100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة",
  "proposal": {
    "title": "سباكه شهر 10",
    "items": [
      { "name": "حنفية", "amount": 100, "quantity": null, "needsReview": false },
      { "name": "جلبه", "amount": 50, "quantity": null, "needsReview": false },
      { "name": "ماسورة", "amount": 90, "quantity": null, "needsReview": false }
    ],
    "projectId": null, "projectName": null,
    "category": null,
    "entityId": null, "entityName": null,
    "date": null,
    "paymentStatus": null,
    "currency": "EGP",
    "statedTotal": null,
    "totalMismatch": false,
    "multipleReceiptsSuspected": false
  },
  "source": "llm",
  "needsConfirmation": true
}
```

### Errors
| Code | When | Client behavior |
|---|---|---|
| `invalid-argument` | Empty text or > 4,000 chars | Inline message under the text field |
| `permission-denied` | No money-mutation role | Same handling as other expense RPCs |
| `failed-precondition` | `OPENROUTER_API_KEY` not configured | "AI unavailable", text kept, manual entry |

An AI timeout or malformed output is **not** an error. The server falls back to rules and returns
`source: "rules"` with every item `needsReview: true`. If there's nothing usable, `items: []`. The
client then shows "Couldn't find items, enter them manually" and keeps the text (Story 2b, scenario 3).

## 4. `processVoiceExpense` (changed, additive)

Existing response fields (`transcript`, `parsed`, `confidence`, `source`, `needsConfirmation`,
`storagePath`) are **kept unchanged** for compatibility. A new field is added:

```json
{ "...existing fields...": "...", "proposal": { /* same shape as organizeExpenseText.proposal */ } }
```

- `source` is now `llm` when the AI proposal is used, and `rules` on fallback.
- `parsed.amount` is set to Σ `proposal.items` (or the rules amount on fallback), so an older client
  still sees a sensible total.
- A new request field `today` (optional) is the same as above. The workspace still comes from the active
  profile, as today.

## 5. Read side (sync)

No RPC. `expenses.items` replicates through the existing `workspace_member` bucket
(`SELECT * FROM expenses`) as JSON text. Visibility is unchanged: anyone who can see an expense sees
its items.
