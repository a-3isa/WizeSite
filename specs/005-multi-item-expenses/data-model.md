# Data Model: Multi-Item Expenses

**Feature**: 005-multi-item-expenses | **Plan**: [plan.md](./plan.md) | **Decisions**: [research.md](./research.md) R1–R4

## 1. Postgres: `expenses` (changed)

Migration `server/migrations/007_expense_items.sql`. It is additive only, with no backfill (R3).

```sql
-- Sum of item amounts, exact in NUMERIC. IMMUTABLE so it can back a CHECK constraint.
CREATE FUNCTION expense_items_total(items jsonb) RETURNS numeric
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT COALESCE(SUM((elem->>'amount')::numeric), 0)
  FROM jsonb_array_elements(items) AS elem
$$;

ALTER TABLE expenses
  ADD COLUMN items JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD CONSTRAINT expenses_items_is_array CHECK (jsonb_typeof(items) = 'array'),
  ADD CONSTRAINT expenses_items_max CHECK (jsonb_array_length(items) <= 100),
  ADD CONSTRAINT expenses_amount_matches_items
    CHECK (items = '[]'::jsonb OR amount = expense_items_total(items));
```

`ADD COLUMN … DEFAULT` with a constant is metadata-only on PG 17, so there is no table rewrite. The
existing rows all have `items = '[]'` and pass the CHECKs. No index is added, because there is no new
query path (constitution constraint).

| Column | Type | Rule |
|---|---|---|
| `amount` | NUMERIC(14,2) | **Unchanged meaning**: the expense total. Equals Σ `items[].amount` when items is non-empty. Still the only value read by recompute, summaries and reports. |
| `description` | TEXT | **Now presented as the expense title** (R4). The wire key is unchanged. `updateExpense` now persists it. |
| `items` | JSONB array | **New.** Ordered list of Expense Items (section 2). `[]` = legacy expense. |
| `input_method` | TEXT | Allowed values extended: `manual` \| `voice` \| `text` (paste + Organize). |
| `transcript` | TEXT | Voice transcript **or pasted text** (FR-018). |
| `source` | TEXT | `llm` (AI proposal used), `rules` (AI failed → rules fallback), `hybrid` (legacy), `''` (manual). |

Everything else (`category`, `project_id`, `entity_*`, `supplier_name`, `payment_*`, `date`,
`currency`, `attachments`, `client_mutation_id`, …) is unchanged and applies to the whole receipt
(FR-004).

## 2. Expense Item (JSON element of `expenses.items`)

```json
{ "id": "k3f9a2", "name": "حنفية", "amount": 100, "quantity": null, "note": "" }
```

| Field | Type | Required | Validation (server RPC; client mirrors it) |
|---|---|---|---|
| `id` | string | yes | Client-generated, 6–36 chars `[A-Za-z0-9_-]`, unique within the expense. Stable key for UI reorder and edit. The server generates one if absent. |
| `name` | string | yes | Trimmed, 1–120 chars (FR-002). |
| `amount` | number | yes | > 0, ≤ 2 decimals (`assertTwoDecimals`), ≤ 999,999,999,999.99. |
| `quantity` | number \| null | no | > 0 if present. **Informational only.** It never multiplies `amount` (spec Assumptions). |
| `note` | string | no | ≤ 200 chars. Default `""`. |

Array rules: 1–100 elements on every new write. The order is the display order (FR-005). Duplicate
names are allowed (spec edge case). Σ amount is computed in integer piastres and must equal `amount`
when the client sends both (R2).

## 3. Legacy fallback (read side, deterministic)

When `items` is `[]` (or missing in an offline-pending payload):

```
effectiveItems = [{ id: "legacy", name: description.trim(), amount: amount, quantity: null, note: "" }]
```

- Display name when `name` is empty: the localized category label (`l10n.expenseCategoryLabel`).
- Display title when `description` is empty: `notes` (current behavior in `expenses_screen.dart`), else
  the category label.
- Nothing is written back until the user edits and saves. At that point the real single item is
  persisted.

## 4. Device replica (PowerSync SQLite)

- `lib/core/sync/schema.dart` → `Table('expenses', …)`: add `Column.text('items')`.
- `lib/core/sync/local_row.dart` → add `'items'` to `_jsonColumns`, so it decodes to `List`.
- No sync-rule change (`SELECT * FROM expenses`). No device index (no new query).

## 5. Dart domain (`lib/features/expenses/domain/`)

```dart
class ExpenseItem {            // new: expense_item.dart
  final String id;
  final String name;
  final double amount;
  final double? quantity;
  final String note;
  factory ExpenseItem.fromMap(Map<String, dynamic>);
  Map<String, dynamic> toMap();
}

class Expense {                // changed
  final List<ExpenseItem> items;             // [] for legacy
  List<ExpenseItem> get effectiveItems;      // section 3 fallback
  String get title => description;           // R4 alias for readability
  int get itemCount => effectiveItems.length;
}
```

`Expense.fromMap` reads `map['items']` through a tolerant parser: a non-list or malformed element
yields `[]` or skips the element and never throws, like `Attachment.listFromDynamic`.

## 6. AI Proposal (transient, never stored)

Returned by `organizeExpenseText` and in `processVoiceExpense.proposal`
([contracts/ai-extraction.md](./contracts/ai-extraction.md)):

| Field | Type | Notes |
|---|---|---|
| `title` | string \| null | Document words stripped. Title numbers kept. |
| `items[]` | `{name: string\|null, amount: number\|null, quantity: number\|null, needsReview: bool}` | Ordered. `needsReview` is true when name or amount is missing or doubtful. |
| `projectId` / `projectName` | string \| null | Only if mentioned *and* matched to a live project. |
| `category` | string \| null | From the allowed list (research R6). |
| `entityId` / `entityName` | string \| null | Supplier. `entityId` only when matched to an existing entity. |
| `date` | ISO date \| null | Relative words resolved against the workspace "today" sent by the client. |
| `paymentStatus` | `unpaid`\|`partial`\|`paid` \| null | Only if mentioned (`مدفوع`, `باقي`, `آجل` …). |
| `currency` | code \| null | One per expense. A conflicting currency on an item → item `needsReview`. |
| `statedTotal` | number \| null | Grand total said or written by the user. |
| `totalMismatch` | bool | `statedTotal != null && statedTotal != Σ items` (FR-017). |
| `multipleReceiptsSuspected` | bool | FR-010b. |
| `source` | `llm` \| `rules` | `rules` = AI failed, fallback used. |

Client merge (`applyProposal`, research R7): it fills only untouched form fields, appends items, and
never overwrites.

Client-derived helpers on the Dart `ExpenseProposal` (they are not on the wire):
- `proposedTitle`: `title`, else the first non-empty item name, else `null` (spec Story 2 scenario 4).
- `toDrafts()`: one editor row per item, or **one empty flagged row** when `items` is empty (spec
  edge case "title-only recording"). The editor never has zero rows.

## 7. State transitions

No new lifecycle. An expense remains `active → archived` (`archiveExpenseWithQuotaRefund`). Archived
expenses can't be edited, and that includes items (existing `failed-precondition`). The monthly quota
still counts **one per expense**, whatever the item count.
