# Research: Multi-Item Expenses

**Feature**: 005-multi-item-expenses | **Date**: 2026-10-19 | **Plan**: [plan.md](./plan.md)

Each decision lists what was chosen, why, and what was rejected. The plan's Technical Context has no
NEEDS CLARIFICATION entries left. They are all resolved here.

---

## R1. Where items are stored

**Decision**: A new `items JSONB NOT NULL DEFAULT '[]'` column on the existing `expenses` table. It is
an ordered array of `{id, name, amount, quantity, note}`. `expenses.amount` stays and always equals
the item sum.

**Rationale**
- **Atomic by construction (FR-025).** An expense and its items are one row, so one INSERT/UPDATE and one
  PowerSync row change. Another device can never see a partial receipt.
- **Zero recompute changes.** `server/src/recompute/project.ts` sums `expenses.amount`. Keeping
  `amount = Σ items` means project/category/weekly summaries, budgets, reports and exports are
  untouched (FR-022, SC-004).
- **Matches the existing pattern.** `attachments` is already a JSONB array on the same row, synced
  as JSON text and decoded by `lib/core/sync/local_row.dart` (`_jsonColumns`).
- **No sync-rule change.** `sync_rules.yaml` uses `SELECT * FROM expenses`, so the new column flows
  automatically. The client schema only needs one `Column.text('items')`.
- Item-level reporting is out of scope (spec Assumptions), so items never need to be queried
  relationally.

**Alternatives considered**
- *Separate `expense_items` table.* Gives relational item queries we don't need. It costs a second
  synced table, a new bucket entry, client-side joins on every list, two-table writes in each RPC, and
  a window where PowerSync checkpoints must be relied on for atomicity. Rejected for now. If
  item-level reports are ever wanted, the JSONB can be exploded into a table by a later migration.
- *Items only in `legacy` JSONB.* Not typed, not constrainable, and hidden from the column mapping.
  Rejected.

## R2. Integrity: total equals the item sum (backend-enforced)

**Decision**: Enforce it in two layers.
1. **RPC validation**: each item has a non-empty trimmed `name` (≤ 120 chars), `amount` > 0 with at
   most 2 decimals (`assertTwoDecimals`), and 1–100 items. The sum is computed in **integer
   piastres** (`Math.round(a*100)`) to avoid float drift. If the payload also sends `amount`, it
   must equal the sum (± 0, compared in piastres), otherwise `invalid-argument`.
2. **Postgres CHECK** via an immutable SQL function `expense_items_total(jsonb) → numeric`, with the
   constraint `items = '[]'::jsonb OR amount = expense_items_total(items)`. Also
   `jsonb_typeof(items) = 'array'`.

**Rationale**: The constitution requires backend-enforced integrity, with the client never the only
enforcement point. Comparing in piastres matches `NUMERIC(14,2)`.

**Alternatives**: client-only validation (violates the constitution). A trigger that overwrites
`amount` (hides client bugs instead of rejecting them).

## R3. Legacy expenses (no items)

**Decision**: **No data backfill.** Rows with `items = '[]'` are legacy. Both server and client
derive one *virtual* item deterministically:
`{id: "legacy", name: <title or "">, amount: expenses.amount}`. When the name is empty, the UI shows
the localized category label. The virtual item is persisted only when the user edits and saves that
expense.

**Rationale**
- Constitution II: "Old records without newer fields MUST load with deterministic fallback values".
  This is exactly that.
- Since no stored money value changes, **no migration verification report is needed** and SC-004
  holds trivially. The CHECK allows `[]`.
- Offline-queued `createExpense` / `updateExpense` payloads created before the app update have no
  `items`. On create, the server treats a missing `items` exactly like a legacy write
  (`items = []`). On update, it looks at the stored row. A legacy row updates as today. A row with
  exactly one item gets that item's amount rewritten to the new total. A row with 2+ items is rejected
  with `failed-precondition`, because a single amount can't be split across several items. That case
  needs another device to have itemized the expense while this one held a queued edit, which is rare
  with 2 users, and the queue already surfaces failed actions. Queued mutations otherwise still replay
  (Principle IV).

**Alternatives**: a SQL backfill writing one item per row. That touches every financial row, needs a
verification report, and needs a non-empty name for rows with empty descriptions. Rejected as
risk without user value.

## R4. The title field

**Decision**: The **existing `description` column/field is the expense title.** The add/edit form
relabels "Description" to "Title" (`العنوان`) and moves it to the top of the form. The wire key stays
`description` (contract preserved). `updateExpense` starts persisting `description`: the server
currently ignores it on update (`server/src/rpc/expenses.ts`), which is a latent bug this feature
must fix because titles are editable.

**Rationale**: `description` is already what lists, dashboard, activity feed and report exports show
(`expenses_screen.dart:1363`, `dashboard_providers.dart:156`, `activity_providers.dart:68`,
`report_export_data_builder.dart`). Reusing it gives titles everywhere with no display-site changes,
and legacy expenses get their existing description as title automatically (FR-023).

**Title fallback when empty (FR-008)** is proposed client-side at save time: the first item name,
else the localized category label. The server accepts an empty description, as it does today.

**Alternatives**: a new `title` column plus backfill from `description`. Two near-duplicate fields
and ~8 display sites to change, for no user-visible gain. Rejected.

## R5. AI-first extraction (clarification Q1)

**Decision**: A new domain service `server/src/domain/voice/services/receipt_extraction.service.ts`
makes **one** structured LLM call (OpenRouter, `OPENROUTER_MODEL`, today `openai/gpt-4o-mini`) with
a strict `json_schema` response format (see [contracts/ai-extraction.md](./contracts/ai-extraction.md)).
It returns a title, ordered items, optional project/category/supplier/date/payment status, a spoken or
written grand total, and a `multipleReceiptsSuspected` flag. Both voice (after transcription) and
pasted text call it.

The existing rules extractor (`rule_extraction.service.ts`) becomes the **fallback only**. When the
LLM call fails (timeout, HTTP error, malformed JSON), the rules extractor produces today's
single-amount result, which is mapped to a one-item proposal with every row flagged, `source: "rules"`.

**Rationale**
- The user explicitly wants AI to handle arbitrary word and line order. Rules-first (today:
  `expense_parser.service.ts` calls the LLM only when `rules.shouldFallback`) cannot pair names with
  amounts in free order.
- Keeping rules as fallback preserves today's behavior when the AI is down (Principle I) and gives
  the user something to correct rather than an empty form.
- One call keeps latency at roughly 2–5 s and cost at fractions of a cent per receipt, with the
  default model.

**Prompt rules** (verified by the eval set, R9):
- Leading document words (`فاتورة`, `بون`, `وصل`, `إيصال`, `حساب`) are not part of the title.
- Numbers that qualify the title (`شهر 10`, `دور 3`, `شقة 5`) stay in the title.
- Currency words (`جنيه`, `ج`, `ج.م`, `EGP`) are not item names.
- Arabic-Indic digits and spoken Egyptian numbers (`مية وخمسين`) become numbers. Normalized text
  from `arabicNormalize.ts` is passed alongside the original.
- Never invent items, amounts, projects or suppliers. Unknown means `null`.
- Do not translate. Names stay in the source language.

**Post-processing (deterministic, server)**: amounts are rounded to 2 dp. Non-positive amounts or empty
names are kept but marked `needsReview`. Project and supplier names are mapped to IDs with the
existing `mapLlmProjectNameToProvided` / `project_matcher` logic (and the same for entities).
Categories outside the expense list are dropped to `null`. `statedTotal` vs Σ items produces
`totalMismatch` (FR-017). Items are capped at 100.

**Alternatives**
- Keep rules-first and add multi-item rules. Fragile across phrasing orders, which is the
  user's stated concern.
- Two LLM calls (title, then items). Twice the latency and cost for no accuracy gain on receipts this
  short.
- On-device model. Larger app, weak Egyptian-Arabic quality. Rejected.

## R6. Which categories the AI may choose

**Decision**: The AI chooses from the **expense categories accepted by `createExpenseWithQuota`**
(`EXPENSE_CATEGORIES` in `server/src/domain/money.ts`), **excluding** `labor` (legacy alias),
`worker` (worker-day entries are a separate flow with days × wage) and `payments`. The current voice
prompt only knows 5 categories (`labor, materials, equipment, transport, other`), which is a gap this
fixes.

## R7. Fields the AI fills, with no overwrite (clarification Q3)

**Decision**: The proposal carries each optional field as `value | null`. The **client** applies a
proposal field only when the form field is still *untouched* (equal to its initial default and not
edited by the user). Each form field tracks a `userEdited` flag. Title and items follow the same rule:
if the user already typed items, the proposal's items are **appended**. Pasted text never replaces
typed rows.

**Rationale**: "Never overwrite manual input" is a UI-state concern. The server can't know what the
user typed. Keeping the server stateless and the merge in one client helper (`applyProposal`) makes it
unit-testable.

## R8. Paste-text entry: RPC, offline, privacy, abuse

**Decision**
- New RPC `organizeExpenseText` (see [contracts/rpc-expense-items.md](./contracts/rpc-expense-items.md)).
  It is `mutating: true` like `processVoiceExpense`, so a retried request returns the first result through
  the existing idempotency table and isn't billed twice. It has a 60 s timeout. No records are
  written.
- **Online only.** The button is disabled offline with a localized hint. The pasted text stays in
  the field (spec edge case "AI unavailable"). Organize is never put in the offline queue: a
  queued AI call has no one to review its result.
- **Input limits**: text is 1–4,000 characters after trim (a long WhatsApp receipt is under 1,500).
  Otherwise `invalid-argument`.
- **Privacy**: the pasted text goes to the same AI provider as voice. The existing first-use AI
  disclosure (`voice_ai_disclosure_store.dart`, key `voice_ai_disclosure_accepted`) is reused and
  its copy generalized from "voice" to "voice and text". Acceptance is shared, so a user who
  accepted for voice is not asked again. Stored `transcript` text gets the same treatment it has today.
- **Cost/abuse**: only authenticated members with money-mutation rights
  (`assertCanMutateMoney`) may call it. The 4,000-character cap bounds the per-call cost. No
  extra rate limiter at 2 users. Revisit if user count grows (noted, not built).
- **Input method**: expenses saved from a paste proposal use `inputMethod: "text"`. Server validation
  is extended from `manual|voice` to `manual|voice|text`. The pasted text is stored in the existing
  `transcript` column (FR-018), so no new column is needed.

## R9. Measuring extraction quality (SC-002, SC-003)

**Decision**
- **Unit tests (CI, no network)**: the LLM client is stubbed. They test prompt construction, schema
  mapping, post-processing (title numbers, currency words, mismatch, flags, ID mapping) and the rules
  fallback path.
- **Live eval (manual, needs `OPENROUTER_API_KEY`)**: `server/test/eval/receipts.jsonl` holds ≥ 20
  realistic Egyptian-Arabic receipts (voice-style transcripts and pasted texts, 1–8 items, varied
  order), including the reference phrase. `npm run eval:receipts` reports per-item exact-match
  accuracy and fails if it is < 85%, or if any title number became an item. It runs before each
  release that touches the prompt or the model, and is documented in quickstart.

**Rationale**: LLM output can't be asserted in CI deterministically. A versioned eval set makes
SC-003 measurable and catches regressions when the model or prompt changes.

## R10. Client UI composition

**Decision**
- A new reusable widget, `ExpenseItemsEditor` (`lib/features/expenses/presentation/widgets/`). It shows
  rows of name + amount (+ optional quantity/note behind an expand control), add/remove/reorder
  (`ReorderableListView`), a live total, inline flags for `needsReview` rows, and blocking validation.
  It is used by **both** `add_expense_screen.dart` (replacing the single amount field for non-worker
  categories) and `voice_review_screen.dart` (replacing its amount field).
- A new `PasteOrganizeSheet` bottom sheet holds a multiline text field, an "Organize with AI" button,
  progress with cancel, and an error state. On success it returns an `ExpenseProposal` that the add
  screen merges via `applyProposal` (R7).
- **Worker category** keeps its existing worker-entry flow (days × wage). The items editor is
  hidden for it.
- **Resource categories with a default rate** (`_recalculateResourceAmount`) keep working: while the
  expense has exactly one item, quantity × rate fills that item's amount. With 2+ items the auto-rate
  is disabled and the hint explains why.
- `add_expense_screen.dart` is already 1,078 lines. New logic goes into the widget, the sheet and a
  small `ExpenseFormItemsController`, not into the screen.

## R11. Search, lists, detail (FR-020, FR-021, FR-024)

**Decision**: Search is in-memory in Dart (`expense_repository.dart:_containsAnyExpenseText`,
`expenses_screen.dart:~794`). Both add the title and every item name to the text matched. The list row
shows `title · N items` when N > 1. The detail screen gets an items section (name, quantity if any,
amount; total row). Report exports keep using `description` (now the title) and amount. Item-level
export is out of scope.

## R12. Release sequencing vs. feature 004

**Decision**: 005 server changes (migration 007 + RPC changes) are deployed **only after the 004
production cutover, once its 7-day Firestore rollback window has closed.** `ops/CUTOVER.md` currently
has no `cutover_at`, so the cutover hasn't happened yet.

**Rationale**: `server/tools/rollback-to-firestore` maps known columns back to Firestore. An `items`
column it does not know would be silently dropped on rollback, which is silent data loss
(Principle II). Waiting avoids changing a one-shot safety tool. Development and staging work can
start immediately on this branch, rebased on 004.

**Alternative**: teach the rollback tool to map `items` → Firestore `items` array. Only worth doing if
005 must ship inside the window. Listed as a contingency task.

**Update 2026-10-20 (owner chose to deploy before the 004 cutover)**: no tool change was needed.
`rowToFirestoreDoc` builds on the generic `rowToDoc`, which copies every column, so `items` already
reaches Firestore as an `items` array with numeric amounts (old Firebase clients ignore it; `amount`
stays the total). This is proven by `server/test/migration/rollback_mapping.test.ts` ("receipt items
survive a rollback"). The VPS had no recorded cutover at deploy time (`cutover_at` blank, data = the
migrated copy), so no live users were affected.
