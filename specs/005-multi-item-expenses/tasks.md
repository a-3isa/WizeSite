---
description: "Task list for 005-multi-item-expenses"
---

# Tasks: Multi-Item Expenses (One Receipt, Many Items)

**Input**: Design documents from `/specs/005-multi-item-expenses/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: INCLUDED. Constitution III requires automated tests for accounting, offline and permission
changes, and the plan names the test files. Write each test task before its implementation task in
the same phase and confirm it fails first.

**Organization**: Grouped by user story, using the spec's story labels: **US1** manual multi-item (P1),
**US2** voice (P2), **US2b** paste + Organize with AI (P2), **US3** edit items (P2), **US4** legacy
expenses (P3). Phase 6, "AI extraction core", is shared by US2 and US2b.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: User story label, used only in story phases
- Paths are relative to the repo root (`server/` = API, `lib/` = Flutter app, `test/` = Flutter tests)

## Conventions every task must follow

- **Money**: compare and sum in integer piastres (`Math.round(x * 100)` in TS, `(x * 100).round()` in
  Dart). Never compare doubles directly.
- **Wire keys**: camelCase in RPC payloads (`items`, `description`, `inputMethod`). Snake_case in SQL.
  The title travels as `description` (research R4).
- **Localization**: add every new string to **both** the `_en` and `_ar` maps in
  `lib/app/localization/app_localizations.dart`, because a missing `_ar` key silently falls back to
  English. Never round-trip that file through PowerShell `Get-Content`/`Set-Content`; edit it with the
  Edit tool, because it contains Arabic.
- **Item JSON shape**: `{id, name, amount, quantity, note}` (data-model §2).

---

## Phase 1: Setup

**Purpose**: Confirm a green baseline and create the scaffolding files.

- [X] T001 Run the baseline gate and record the results in the PR description: `cd server && npm test && npm run test:integration`, then `flutter analyze 2>&1 | Select-Object -First 80` and `flutter test --reporter compact 2>&1 | Select-Object -Last 50`. If anything fails before any change, stop and report it.
- [X] T002 [P] Add the npm script `"eval:receipts": "npm run build && node dist/test/eval/eval_receipts.js"` to `server/package.json`, next to `test:parity`.
- [X] T003 [P] Add localization keys to both `_en` and `_ar` maps in `lib/app/localization/app_localizations.dart`:
  - `expenseTitle` (Title / العنوان)
  - `expenseItems` (Items / البنود)
  - `addItem` (Add item / إضافة بند)
  - `itemName` (Item / البند)
  - `itemAmount` (Amount / المبلغ)
  - `itemQuantityOptional` (Quantity (optional) / الكمية (اختياري))
  - `itemNoteOptional` (Note (optional) / ملاحظة (اختياري))
  - `itemsTotal` (Total / الإجمالي)
  - `itemsCount` (`{count} items` / `{count} بنود`)
  - `itemNeedsReview` (Check this item / راجع هذا البند)
  - `itemNameRequired` (Item name is required / اسم البند مطلوب)
  - `itemAmountRequired` (Enter an amount greater than zero / أدخل مبلغًا أكبر من صفر)
  - `cannotRemoveLastItem` (An expense needs at least one item. Delete the expense instead. / المصروف يحتاج بندًا واحدًا على الأقل، احذف المصروف بدلًا من ذلك)
  - `pasteText` (Paste text / لصق نص)
  - `organizeWithAi` (Organize with AI / نظّم بالذكاء الاصطناعي)
  - `organizing` (Organizing… / جارٍ التنظيم…)
  - `organizeNoItemsFound` (Couldn't find items, enter them manually / لم نجد بنودًا، أدخلها يدويًا)
  - `organizeOfflineHint` (Organizing needs internet / التنظيم يحتاج اتصالًا بالإنترنت)
  - `multipleReceiptsWarning` (This text may contain more than one receipt / قد يحتوي النص على أكثر من فاتورة)
  - `statedTotalMismatch` (Stated total {stated} differs from items total {sum} / الإجمالي المذكور {stated} يختلف عن مجموع البنود {sum})
  - `autoRateSingleItemOnly` (Rate × quantity applies only with one item / السعر × الكمية يعمل مع بند واحد فقط)

  Keep the existing `description` key, because other screens still use it.

---

## Phase 2: Foundational (blocks every story)

**Purpose**: The data shape that every story reads and writes, on the server, in sync, and in the
Dart model.

**⚠️ CRITICAL**: No story work starts until this phase is green.

### Tests first

- [X] T004 [P] Write unit tests in `server/test/unit/expense_items.test.ts` for the pure helper planned in T006.
  - Valid 3-item input returns normalized items, and the total is 240.
  - Missing `id` gets a generated id. Duplicate ids are rejected.
  - Empty or whitespace name, a 121-char name, amount ≤ 0, amount with 3 decimals, non-numeric amount, and `quantity` ≤ 0 are each rejected with the messages in `contracts/rpc-expense-items.md` §1 (1-based `Item {i}`).
  - `[]` and 101 items are rejected with "Expense must have between 1 and 100 items".
  - Totals in piastres: `0.1 + 0.2` items equal an `amount` of `0.3`.
  - `amount` mismatch is rejected with "Amount must equal the sum of items".
  - `items` absent returns `null`, which means a legacy write.
- [X] T005 [P] Write Flutter unit tests in `test/features/expenses/domain/expense_item_test.dart`.
  - `ExpenseItem.fromMap`/`toMap` round-trip.
  - `Expense.fromMap` with `items` as a List, as a JSON-decoded list, missing, as a non-list (`"x"`), and with one malformed element. None of these throw, and the malformed element is skipped.
  - `effectiveItems` on a legacy expense (`items` empty) returns one item `{id:'legacy', name: description.trim(), amount}`.
  - `title` returns `description`.
  - `itemCount` is correct.

### Server

- [X] T006 Create `server/src/rpc/expense_items.ts`.
  - Export `type ExpenseItem = {id: string; name: string; amount: number; quantity: number | null; note: string}`.
  - Export `parseExpenseItems(data: Record<string, unknown>): {items: ExpenseItem[]; total: number} | null`. It returns `null` when `data.items` is `undefined`/`null`, and otherwise validates per data-model §2.
    - Use `assertTwoDecimals` from `./validation`.
    - Throw `RpcError("invalid-argument", …)` with the exact messages from the contract.
    - Generate missing ids with `newDocId().slice(0, 12)`.
    - Check `id` against `^[A-Za-z0-9_-]{6,36}$`.
  - Export `assertAmountMatchesItems(amount: number | null, total: number)`, comparing `Math.round(x*100)`.

  Make T004 pass.
- [X] T007 Create migration `server/migrations/007_expense_items.sql` exactly as in data-model §1: function `expense_items_total(jsonb)`, column `items`, and constraints `expenses_items_is_array`, `expenses_items_max` and `expenses_amount_matches_items`. Add a `-- Down Migration` section that drops the three constraints, the column and the function, following the style of `006_tombstones.sql`. Run `npm run migrate` against `compose.dev.yml`.
- [X] T008 Extend `server/test/integration/expenses_payments.test.ts` with a `describe("expense items")` block that uses the existing helpers in `server/test/integration/helpers.ts`.
  - **Create with items**: 3 items and no `amount`. The stored `amount` is 240, `items` is stored in order, and `project_summaries`/project metrics show +240.
  - **Create with items plus a matching amount**: succeeds.
  - **Create with items plus a mismatching amount**: `invalid-argument`, and no row is inserted.
  - **Create without items** (legacy payload): succeeds, `items = []`, `amount` is the payload amount.
  - **Direct SQL** `UPDATE expenses SET amount = 1 WHERE id = …` on an itemized row fails with the `expenses_amount_matches_items` CHECK.
  - **Quota**: the 3-item create consumes `expenses_count` by exactly 1.
  - **`inputMethod: "text"`** is accepted, and `"foo"` is rejected with "inputMethod must be manual, voice or text".
- [X] T009 Update `createExpenseWithQuotaForUser` in `server/src/rpc/expenses.ts`.
  - Call `parseExpenseItems(data)` before `existingMutation`.
  - When it returns items, set `amount = total`. If `data.amount` is present, call `assertAmountMatchesItems(requireMoney(data,"amount"), total)`.
  - When it returns `null`, keep `positiveAmount(data)`.
  - Add `items` to the INSERT column list as `${sql.json((parsed?.items ?? []) as never)}`.
  - Extend the `inputMethod` check to `manual|voice|text`, with the new message.
  - Leave `description` handling unchanged: trimmed, **no server length cap**. Old app builds send `description = notes`, which can be long, and rejecting or truncating those would break queued creates. The 200-char limit is a UI `maxLength` on the title field (T020).

  Make the create cases of T008 pass.
- [X] T010 Update `updateExpenseForUser` in `server/src/rpc/expenses.ts`, following contract §2.
  - Extend `expenseInWorkspace`'s `SELECT … FOR UPDATE` to also return `items`.
  - Call `parseExpenseItems(data)`. When it is non-null, set `amount = total` (with an optional match check) and write `items = ${sql.json(items)}`.
  - When it is null (legacy payload), branch on the **stored** items:
    - `[]`: keep the current `positiveAmount(data)` path and leave `items` untouched.
    - Exactly 1 item: use `positiveAmount(data)` and write `items` with that one item's `amount` replaced. Keep its `id`, `name`, `quantity` and `note`.
    - 2 or more items: throw `RpcError("failed-precondition", "This expense has several items; edit its items to change the amount")`.
  - **Persist `description`** only when `data.description` is a string, as `description = ${trimmed}`. When it is `undefined`/`null`, leave the column unchanged (use a conditional like `attachments`).
  - In the RPC handler, catch Postgres SQLSTATE `23514`, log it, and rethrow `RpcError("internal", "Expense items integrity check failed")`. It is a server bug, never a user error.

  Add integration cases to T008's block:
  - Update with items replaces the items and the total, and project metrics follow.
  - A legacy payload (no `items`) on a legacy row updates the amount, and `items` stays `[]`.
  - A legacy payload on a 1-item row updates both `amount` and `items[0].amount`, and keeps the item `id` and `name`.
  - A legacy payload on a 3-item row gives `failed-precondition` with the exact message, and the row is unchanged.
  - A description update persists. A payload without `description` leaves the title unchanged.
  - Updating an archived expense returns `failed-precondition`, as before.

### Sync + Dart model

- [X] T011 [P] Add `Column.text('items'),` after `Column.text('attachments'),` in the `expenses` table of `lib/core/sync/schema.dart`. Add `'items'` to `_jsonColumns` in `lib/core/sync/local_row.dart`.
- [X] T012 [P] Create `lib/features/expenses/domain/expense_item.dart` with an immutable `ExpenseItem` class: `id`, `name`, `amount` (double), `quantity` (double?), and `note` (String, default `''`).
  - Include `fromMap`, tolerant like `Attachment.listFromDynamic`. Numbers can arrive as `num` or `String`.
  - Include `toMap`, `copyWith`, value equality, and `static List<ExpenseItem> listFromDynamic(Object? raw)`, which accepts a List or a JSON string, skips bad elements and never throws.
  - Include `static String newId()`: 10 random `[a-z0-9]` chars from `Random.secure()`.
- [X] T013 Update `lib/features/expenses/domain/expense.dart`.
  - Add the constructor param `this.items = const []` and the field `final List<ExpenseItem> items`.
  - In `fromMap`, set `items: ExpenseItem.listFromDynamic(map['items'])`.
  - Add the getters `String get title => description;`, `List<ExpenseItem> get effectiveItems` (data-model §3) and `int get itemCount`.

  Make T005 pass.
- [X] T014 Update the offline overlay in `lib/features/expenses/data/expense_repository.dart`.
  - In `_expenseFromCreateAction` (~line 510), pass `items: ExpenseItem.listFromDynamic(payload['items'])`, and set `inputMethod` from `payload['inputMethod'] ?? 'manual'` instead of the hard-coded `'manual'`.
  - In the `updateExpense` overlay loop (~line 348), pass `items: action.payload.containsKey('items') ? ExpenseItem.listFromDynamic(action.payload['items']) : current.items`.
  - Create `test/features/expenses/data/expense_repository_items_overlay_test.dart` (T032 adds to this file): a pending create action with 2 items shows 2 items, and a pending update with items replaces them.
- [X] T015 Update `lib/core/services/workspace_mutation_service.dart`.
  - Add `List<Map<String, dynamic>>? items` to `createManualExpense` and `updateExpense`.
  - When it is non-null, put it into the payload as `'items'`, and set `'amount'` to the item sum rounded to 2 dp in piastres.
  - When `inputMethod` is `'text'`, pass it through (no client validation change is needed beyond the type).
  - In `updateExpense` only, replace `'description': description ?? notes ?? ''` with: put `'description'` only when `description != null`. Never fall back to `notes`, because the server now persists the title on update (contract §2). Keep `createManualExpense` as it is.
- [X] T016 Update the repository signatures in `lib/features/expenses/data/expense_repository.dart`.
  - Add `List<Map<String, dynamic>>? items` to the abstract `createExpense` (~line 32) and `updateExpense` (~line 54), and to their implementations (~lines 211 and 255). Pass it through to `_mutationService.createManualExpense(items: …)` and `_mutationService.updateExpense(items: …)`.
  - Also add `String? inputMethod` (default `'manual'`), `String? transcript` and `String? source` to the abstract and concrete `createExpense`, and pass them to `createManualExpense`, which already accepts them. T056 needs this so a pasted expense keeps its text (FR-018) and is saved as `text`. Update every fake or mock implementing that interface under `test/` (find them with Grep for `implements ExpenseRepository` and `extends ExpenseRepository`) so the suite still compiles.

**Checkpoint**: The server accepts and enforces items, devices replicate them, and the model reads them.
The UI is unchanged and existing behavior still passes T001's suites.

---

## Phase 3: User Story 1 — Record one receipt with several items manually (P1) 🎯 MVP

**Goal**: Title + N items + live total + shared fields + receipt files, saved as one expense, and shown
as one row with an item breakdown.

**Independent Test**: quickstart §4 "Story 1". Create "سباكه شهر 10" with حنفية 100 / جلبه 50 /
ماسورة 90 and a photo, save, reopen. You should see three item lines, total 240, the photo, and the
project total +240.

### Tests first

- [X] T017 [P] [US1] Create the widget test `test/widget/expense_items_editor_test.dart`.
  - Starts with one empty row.
  - "Add item" appends a row.
  - Typing amounts 100/50/90 shows a total of 240.00 (formatted like the existing amount fields with `ThousandsSeparatorInputFormatter`).
  - Delete removes a row. Deleting the last row shows `cannotRemoveLastItem` and keeps the row.
  - `validate()` returns false and marks the row with an empty name or a 0 amount.
  - A row created with `needsReview: true` shows the `itemNeedsReview` indicator until edited.
  - Reorder via `ReorderableListView` changes the order passed to `onChanged`.
  - 100 rows render without overflow. The 101st "Add item" is disabled.
- [X] T018 [P] [US1] Extend `test/widget/add_expense_screen_test.dart`.
  - The title field appears first, with key `qa_add_expense_title`.
  - A materials expense with 3 items calls `ExpenseRepository.createExpense` (the screen's real call path, `add_expense_screen.dart:~283`) with `items` (3 maps, in order), `amount: 240` and `description: 'سباكه شهر 10'`. Use the test's existing fake repository, extended in T016.
  - An empty title saves with `description` equal to the first item name (FR-008).
  - An empty title with an empty first item name is blocked by validation first.
  - Worker category hides the items editor and still calls the worker-entry path.
  - An equipment entity with a default rate and one item: quantity 3 × rate 200 fills the item amount to 600. With 2 items the auto-rate is off and `autoRateSingleItemOnly` is shown.
  - A single-item save needs no extra taps compared with the old amount field (FR-009). The editor starts with one row, focused after the title.
  - **Update the existing tests that drive the removed amount field** so they target the items editor and keep the behavior they protect:
    - `'empty amount shows what to do instead of saving'`: an empty item amount blocks save and shows the row error.
    - `'resource category shows saved resources and calculates amount'`: the rate × quantity result lands in the first item's amount.
    - Any other test in this file that enters text into the old amount field.

    Extend `_FakeExpenseRepository` (`implements ExpenseRepository`) with the new T016 parameters and record them for assertions.

### Implementation

- [X] T019 [US1] Create `lib/features/expenses/presentation/widgets/expense_items_editor.dart`.
  - `ExpenseItemsEditor` is a StatefulWidget with these params: `List<ExpenseItemDraft> initialItems`, `ValueChanged<List<ExpenseItemDraft>> onChanged`, `String currency`, and an `ExpenseItemsEditorController? controller`.
  - The controller exposes `bool validate()`, `List<ExpenseItemDraft> get items`, `void appendItems(List<ExpenseItemDraft>)`, `void setFirstItemAmount(double)`, `double get total` (computed in piastres) and `bool get hasUserEdits`.
  - Define `ExpenseItemDraft` in the same file: `id`, `name`, `amountText`, `quantityText`, `note`, `needsReview`, and `toItemMap()` → data-model §2 shape.
  - Rows: name `BuildTextField` (key `qa_item_name_{index}`) and amount field (key `qa_item_amount_{index}`, numeric keyboard, `ThousandsSeparatorInputFormatter`, parsed with `NumberParser.parseDouble`). An expand icon reveals quantity and note. A delete icon. A drag handle.
  - Below the rows: an "Add item" button (disabled at 100) and a sticky total row (`itemsTotal`).
  - RTL-safe: use `EdgeInsetsDirectional`, not `EdgeInsets.only(left/right)`.

  Make T017 pass.
- [X] T020 [US1] Update `lib/features/expenses/presentation/screens/add_expense_screen.dart`.
  - Move the description field to the top and relabel it `l10n.t('expenseTitle')`, key `qa_add_expense_title`, with `maxLength: 200`. Keep `_descriptionController`.
  - For every category except `AccountingCategories.worker`, replace the single amount `TextField` (~line 691) with `ExpenseItemsEditor`. Keep `_amountController` only for the worker path.
  - In `_save()`, call `itemsController.validate()`. Compute `amount` from `itemsController.total`. If the title is empty, set the description to the first item name, else `l10n.expenseCategoryLabel(category)`. Pass `items: itemsController.items.map((d) => d.toItemMap()).toList()` to both repository calls the screen already makes: `ExpenseRepository.createExpense` (~line 283) and `ExpenseRepository.updateExpense` (~line 315). Both are extended in T016.
  - Rewire `_recalculateResourceAmount` to call `itemsController.setFirstItemAmount(...)` only when `items.length == 1`. Otherwise show `autoRateSingleItemOnly`. The quantity field for resource categories also writes the first item's `quantity`.
  - Keep any new logic over ~40 lines in the widget or controller, not in this 1,078-line screen.

  Make T018 pass.
- [X] T021 [P] [US1] Update `lib/features/expenses/presentation/screens/expense_detail_screen.dart`.
  - Add an "Items" section above attachments. List `expense.effectiveItems` with one line per item: the name (or the localized category label when empty), the quantity in muted text if non-null, and the amount formatted like the existing amount display. Then add a divider and an `itemsTotal` row equal to `expense.amount`.
  - Use `expense.title` (fallback `notes`, then the category label) as the screen header.
  - Lines ~245–280 are the **duplicate** action (covered by T022). Edit navigation is covered by T028.
- [X] T022 [US1] Fix the **duplicate expense** action in `lib/features/expenses/presentation/screens/expense_detail_screen.dart` (~lines 245–280, the `expenseRepositoryProvider.createExpense(...)` call).
  - Pass `items: expense.items.isEmpty ? null : expense.items.map((i) => i.copyWith(id: ExpenseItem.newId()).toMap()).toList()`, so each copy gets fresh item ids. A legacy expense stays legacy.
  - Pass `description: expense.description`, keeping the existing fields.
  - Add a widget test to `test/widget/expense_detail_screen_test.dart` (create it if missing): duplicating a 3-item expense calls `createExpense` with 3 items whose ids differ from the source, `amount: 240` and the same title. Duplicating a legacy expense sends no `items`.
- [X] T023 [P] [US1] Update the list row in `lib/features/expenses/presentation/screens/expenses_screen.dart` (~line 1340) and `lib/features/expenses/presentation/models/expense_group.dart` (~line 84).
  - The primary label is `expense.title` when non-empty, else the current label.
  - In the subtitle `parts`, replace the trailing description part with `l10n.t('itemsCount', params: {'count': '${expense.itemCount}'})` when `itemCount > 1`.
  - Keep the attachment count part.
  - Add a widget test case to `test/widget/expenses_screen_filter_test.dart` (where rows render): a 3-item expense row shows its title and "3 items".
- [X] T024 [US1] Update search (FR-024). Run it after T023, which edits the same `expenses_screen.dart`.
  - In `_containsAnyExpenseText` in `lib/features/expenses/data/expense_repository.dart` (~line 500), add `...expense.items.map((i) => i.name)` to the matched values.
  - Add the item names to the haystack string in `lib/features/expenses/presentation/screens/expenses_screen.dart` (~line 794).
  - Add a case to `test/widget/expenses_screen_filter_test.dart`: searching "ماسورة" finds the plumbing expense.
- [ ] T025 [US1] Run the quickstart §4 "Story 1" checklist on an emulator against the local backend, including the duplicate check and the stopwatch timing step (SC-001: < 90 s). Note the results and the measured time in the PR.

**Checkpoint**: US1 is fully usable. Multi-item receipts can be created by hand with no AI.

---

## Phase 4: User Story 3 — Edit items of an existing expense (P2)

**Goal**: Change, add, remove and reorder items on a saved expense, and have the total update everywhere.

**Independent Test**: quickstart §4 "Story 3". Pipe 90→95, add تيفلون 10, and the total becomes 255 in
the detail, the list, the project total and on the second phone.

- [X] T026 [P] [US3] Extend `test/widget/add_expense_screen_test.dart` with an edit-mode group.
  - Opening with an `expenseId` pre-fills the title and the 3 item rows in their stored order.
  - Editing one amount and adding a row calls `updateExpense` with 4 items, `amount: 255` and the new `description`.
  - Removing down to 1 row and then trying to remove it shows `cannotRemoveLastItem`.
  - Editing a legacy expense (`items: []`) pre-fills one row from `effectiveItems`, and the save sends that row as a real item.
- [X] T027 [US3] In `lib/features/expenses/presentation/screens/add_expense_screen.dart`, in edit mode (~line 126 where `expense` is loaded), seed `ExpenseItemsEditor.initialItems` from `expense.effectiveItems`, mapping each to an `ExpenseItemDraft` and keeping `id`. Always send `items` on update for non-worker categories, because the server rejects amount-only updates of itemized rows (T010). Make T026 pass.
- [X] T028 [US3] In `lib/features/expenses/presentation/screens/expense_detail_screen.dart`, make sure the edit action passes the current `expense` (with `items`) to the edit route, so no extra fetch is needed. Confirm that the archived expense edit button stays hidden (existing behavior).
  - *Implemented as:* no router change was needed. The edit screen already re-fetches the expense in `_prefill` (`getExpense`), and that now carries `items`.
- [X] T029 [US3] Sweep for update payloads that would hit the new `failed-precondition` (contract §2). Grep `lib/` for every caller of `ExpenseRepository.updateExpense` and `WorkspaceMutationService.updateExpense`. Any caller that edits a non-worker expense must send `items` (built from `expense.effectiveItems` when the user did not touch the items). Fix each caller found, and add a case for it to `test/widget/add_expense_screen_test.dart` or that caller's own test.
- [ ] T030 [US3] Run the quickstart §4 "Story 3" checklist on two devices or emulators, including reorder persistence, the title change appearing on the second device, and attaching an extra receipt file to a saved expense (FR-019 "later").

**Checkpoint**: US1 + US3 = complete manual MVP.

---

## Phase 5: User Story 4 — Existing expenses keep working (P3)

**Goal**: Pre-feature expenses and pre-update offline queue entries load, display and total
identically.

**Independent Test**: quickstart §4 "Story 4" and §3 "totals snapshot" are identical before and after
migration 007.

- [X] T031 [P] [US4] Add a migration test `server/test/integration/expense_items_migration.test.ts`.
  - Insert 3 expenses with the pre-007 shape, using the column list from `002_accounting.sql`.
  - Run migration 007 through the existing integration DB setup.
  - Assert every row has `items = '[]'`, `amount` is unchanged, and `SELECT project_id, sum(amount)` is identical before and after.
  - Assert `recomputeProject` totals are unchanged.
- [X] T032 [P] [US4] Add a Flutter test case in `test/features/expenses/data/expense_repository_items_overlay_test.dart`. A pending `createExpense` offline action **without** `items` (old app build payload) builds an `Expense` with `items: []`, `effectiveItems.length == 1` and the original amount.
- [X] T033 [US4] Make sure every display of an item name or title falls back correctly for legacy rows: an empty `effectiveItems[0].name` shows `l10n.expenseCategoryLabel(expense.category)`, and an empty title shows `notes`, then the category label. Use one helper, `expenseDisplayTitle(Expense, AppLocalizations)` in `lib/features/expenses/presentation/models/expense_group.dart`, from the detail screen (T021) and the list (T023).

**Checkpoint**: Legacy safety is proven. Phases 1–5 can ship alone as the manual-only release.

---

## Phase 6: AI extraction core (shared by US2 and US2b)

**Purpose**: One structured LLM call turns text into an AI Proposal, with a rules fallback
([contracts/ai-extraction.md](./contracts/ai-extraction.md)).

**⚠️** US2 and US2b both depend on this phase.

### Tests first

- [X] T034 [P] Write unit tests in `server/test/unit/voice/receipt_extraction.test.ts`. Inject a stub `fetch` (the service must accept `fetchImpl?: typeof fetch`).
  - The prompt contains the original and normalized text, project names, supplier names, today and the default currency, and **no ids**.
  - The prompt contains every contract instruction, 1–11. Assert distinctive phrases from rule 3 (title numbers), rule 6 (stated total) and rule 11 (quantity/line total).
  - A stub item `{name: "حنفية", quantity: 2, amount: 200}` maps to a proposal item with `quantity: 2` and `amount: 200`, never multiplied.
  - The request uses `response_format.json_schema.strict = true`. The category enum equals `EXPENSE_CATEGORIES` minus `labor`, `worker` and `payments`.
  - A stub response for the reference phrase maps to a proposal with title `سباكه شهر 10` and 3 items, all `needsReview: false`.
  - Post-processing: amount `-5` gives `null` and `needsReview`. `100.456` becomes `100.46`. An empty name gives `needsReview`. An item currency `USD` with expense currency `EGP` gives `needsReview`. 120 items are capped to 100 and set `multipleReceiptsSuspected`. A `statedTotal` of 250 against an item sum of 240 sets `totalMismatch: true`. A date 3 days after `today` becomes `null`. An unknown project name gives `projectId: null`. A known supplier name gives `entityId`.
  - Fallback: a stub that throws, returns HTTP 500, or returns malformed JSON makes the result come from the rules extractor with `source: "rules"`, ≤ 1 item and `needsReview: true`. If the rules find nothing, `items: []`.
  - The raw text is never passed to the logger. Assert this with a spy logger.

### Implementation

- [X] T035 [P] Add the proposal types to `server/src/domain/voice/types/expense.ts`: `ProposalItem`, `ExpenseProposal` and `ExpenseProposalResponse` as in data-model §6 and contracts §3. Add `proposal?: ExpenseProposal` to `ProcessVoiceExpenseResponse`, and widen `ParseSource` (it already has `llm`).
- [X] T036 [P] Create `server/src/domain/voice/services/entity_matcher.service.ts`, exporting `matchEntityName(name, entities: {id,name}[]) → {entityId, entityName}`. Mirror `mapLlmProjectNameToProvided` in `llm_extraction.service.ts`: normalize with `normalizeTranscript`, try an exact match, then containment either way. An unmatched name returns `{entityId: null, entityName: name}`.
- [X] T037 Create `server/src/domain/voice/services/receipt_extraction.service.ts`.
  - Export `extractReceipt(params: {text, projects, entities, currency, today, openRouterApiKey, model, timeoutMs?: number /*20000*/, fetchImpl?, logger?}) : Promise<{proposal: ExpenseProposal; source: "llm" | "rules"}>`.
  - Build the prompt from **all** instructions (1–11) in the contract, including rule 11 (quantity is informational, the amount is the line total), and use the strict schema verbatim. Generate the category enum from `EXPENSE_CATEGORIES`.
  - Reuse `safeJsonParse` (export it from `llm_extraction.service.ts`) and `normalizeTranscript`.
  - Apply the post-processing table. On any failure, call `extractExpenseByRules` (from `rule_extraction.service.ts`) and map its single amount and note to ≤ 1 item with `needsReview: true`.
  - Log `{model, latencyMs, itemCount, source, fallbackReason}` only.

  Make T034 pass.
- [X] T038 Add a workspace-scoped loader to `server/src/rpc/voice.ts`: `loadExtractionContext(sql, workspaceId) → {projects (≤100 live, by created_at), entities (≤200 from the entities table, non-archived, by name)}`. Refactor the existing `workspaceProjects(sql, uid)` to resolve the active workspace id and then call it.
- [X] T039 [P] Create the eval set `server/test/eval/receipts.jsonl` with ≥ 20 lines `{id, input, expected: {title, items:[{name, amount}]}}`. Include:
  - the reference phrase
  - items before the title
  - amounts after the names ("حنفية بـ 100")
  - Arabic-Indic digits
  - spoken numbers ("مية وخمسين")
  - title numbers (`شهر 10`, `دور 3`, `شقة 5`)
  - chatter ("تمام يا باشا", greetings)
  - one-line and multi-line pasted layouts
  - a single-item receipt
  - an 8-item receipt
  - a stated total
  - an English/Arabic mix
  - a quantity case (`2 حنفية بـ 200` → `{name: "حنفية", quantity: 2, amount: 200}`; the expected value includes `quantity`)
- [X] T040 Create `server/test/eval/eval_receipts.ts`.
  - Read `receipts.jsonl` from `path.resolve(__dirname, "../../../test/eval/receipts.jsonl")`, because tsc doesn't copy `.jsonl`.
  - Call `extractReceipt` with the real `OPENROUTER_API_KEY`/`OPENROUTER_MODEL` from `server/.env`. Use `loadConfig` from `server/src/config.ts`.
  - Score item exact-match (normalized name + amount) and title exact-match. Count title-number violations (an item amount equal to a number that appears in the expected title).
  - Score `quantity` when the expected item has one.
  - Measure the wall-clock latency of each `extractReceipt` call. Print p50 and p95.
  - Print a table plus totals. Exit 1 if item accuracy is < 85%, there are any title-number violations, or p95 latency is > 8 s (plan Performance Goals).
  - *Implemented as:* `loadConfig` needs DATABASE_URL, FILES_ROOT and other unrelated settings, so the eval reads only `OPENROUTER_API_KEY`/`OPENROUTER_MODEL`, loading `server/.env` with `process.loadEnvFile`.

**Checkpoint**: `npm test` is green and `npm run eval:receipts` passes (≥ 85%, 0 violations). Record the
model and accuracy in the PR.

---

## Phase 7: User Story 2 — Speak a receipt and let the AI split title and items (P2)

**Goal**: The voice recording produces a reviewable proposal of title and items (and mentioned
fields), in any phrasing order.

**Independent Test**: quickstart §4 "Story 2". The reference phrase gives title `سباكه شهر 10` and 3
items. The reordered phrase gives the same result. A stated total of 250 shows the mismatch warning.

### Tests first

- [X] T041 [P] [US2] Extend `server/test/integration/voice.test.ts` (stub OpenRouter the way the file already does).
  - The response keeps every legacy field (`transcript`, `parsed`, `confidence`, `source`, `needsConfirmation`, `storagePath`) **and** adds `proposal` with the 3 items.
  - `parsed.amount` equals Σ proposal items (240).
  - With the extraction stub failing, `source: "rules"` and the proposal items are flagged.
  - An optional `today` in the payload is honored.
- [X] T042 [P] [US2] Extend `test/widget/voice_review_screen_test.dart`.
  - A response with `proposal` (3 items, title) renders the `ExpenseItemsEditor` with 3 rows and the title field pre-filled.
  - The proposal project, category and payment status pre-fill their fields.
  - A `needsReview` row blocks save until it is fixed.
  - `totalMismatch` shows `statedTotalMismatch` with both numbers.
  - `multipleReceiptsSuspected` shows `multipleReceiptsWarning`.
  - Save calls `ExpenseSaveService.saveVoiceExpense` with `items`, `amount: 240`, `description` = title and `source: 'llm'`.
  - A response **without** `proposal` (old server) falls back to one row from `parsed.amount`/`parsed.note`.
  - A single-item proposal with `title: null` and item `رمل 2000` pre-fills the title field with `رمل` (Story 2 scenario 4).
  - A title-only proposal (`items: []`, title `سباكه`) shows the title and **one** empty flagged row, and save is blocked until the row is completed.
  - **Update the existing tests in this file that use `qa_voice_review_amount`** (the removed single amount field), so they drive the items editor instead and keep their original assertions about save, validation and confidence display.

### Implementation

- [X] T043 [US2] In `server/src/rpc/voice.ts` `processVoiceExpenseForUser`, after transcription:
  - Load `loadExtractionContext` for the active workspace and call `extractReceipt({text: transcript, …, today: payload.today ?? cairoToday()})`.
  - Build the legacy response fields from the proposal: `parsed.amount = Σ items or null`, `parsed.note = title`, `parsed.category/matchedProject*` from the proposal, and `source` from the extraction.
  - Attach `proposal`.
  - Keep `parseExpenseFromTranscript` reachable only through the fallback inside `extractReceipt`.
  - Add the helper `cairoToday()` using `Intl.DateTimeFormat("en-CA", {timeZone: "Africa/Cairo"})`.

  Make T041 pass.
- [X] T044 [P] [US2] Create `lib/features/expenses/domain/expense_proposal.dart`. It mirrors data-model §6: `ExpenseProposal`, plus `ProposalItem` with `fromMap`, tolerant of missing keys and old servers.
  - Add `List<ExpenseItemDraft> toDrafts()`, which maps each proposal item to an `ExpenseItemDraft` with a new id and `needsReview`. When `items` is empty, it returns **one empty draft with `needsReview: true`**, because the editor always has at least one row (spec edge case "title-only recording").
  - Add `String? get proposedTitle`: `title` when non-empty, otherwise the first non-empty item name, otherwise `null` (spec Story 2 scenario 4).
  - *Implemented as:* `ExpenseItemDraft` moved to `lib/features/expenses/domain/expense_item_draft.dart` (re-exported by the editor), so the domain proposal model can build editor rows without importing UI code.
- [X] T045 [US2] Update `lib/features/voice_expense/domain/voice_expense_models.dart`. Add `final ExpenseProposal? proposal` to `VoiceExpenseParseResponse`, parsed from `map['proposal']` when it is a Map. Send `today` (device local date `YYYY-MM-DD`) in the request built in `lib/features/voice_expense/data/voice_expense_repository.dart`.
- [X] T046 [US2] Update `lib/core/services/expense_save_service.dart` `saveVoiceExpense`. Add `List<Map<String, dynamic>>? items` and `String? description`, and pass them to `createManualExpense`, along with `paymentStatus` and `entityName` when they are provided.
- [X] T047 [US2] Update `lib/features/voice_expense/presentation/screens/voice_review_screen.dart`.
  - Add a title field above the items, pre-filled with `response.proposal?.proposedTitle` (still editable).
  - Replace the single amount field (key `qa_voice_review_amount`, ~line 317) with `ExpenseItemsEditor`. Seed it from `response.proposal?.toDrafts()`, or from one draft built from `parsed.amount`/`parsed.note` when `proposal` is null.
  - Pre-fill project, category, supplier, date and payment status from the proposal when non-null.
  - Show the `statedTotalMismatch` and `multipleReceiptsWarning` banners using the existing `_ErrorBanner` style, as info rather than error.
  - `_saveConfirmed` validates the editor and passes `items`, `amount` (the total) and `description` (the title).
  - Keep the transcript visible (FR-018).

  Make T042 pass.
- [ ] T048 [US2] Run the quickstart §4 "Story 2" checklist on a real device: reference phrase, reordered phrase, stated total mismatch, airplane mode during processing, and the stopwatch timing step (SC-001: < 45 s). Note the measured time in the PR.

**Checkpoint**: Voice produces multi-item receipts.

---

## Phase 8: User Story 2b — Paste receipt text and "Organize with AI" (P2)

**Goal**: Paste text on the add-expense screen, tap "Organize with AI", and the form fills its title,
items and mentioned fields without overwriting what the user already entered.

**Independent Test**: quickstart §4 "Story 2b". Pasting the reference text and tapping Organize fills
the form with a total of 240. A pre-selected project is kept. Typed rows are kept and the AI rows are
appended.

### Tests first

- [X] T049 [P] [US2b] Add integration tests to `server/test/integration/voice.test.ts` in a `describe("organizeExpenseText")` block (stub OpenRouter).
  - The reference text returns the contract §3 response.
  - Empty text and 4,001-char text return `invalid-argument`.
  - A caller without the money-mutation role gets `permission-denied`.
  - The workspace's projects and entities are used (not the active profile's).
  - A retry with the same `X-Idempotency-Key` returns an identical body and calls the stub **once**.
  - A missing API key gives `failed-precondition`.
- [X] T050 [P] [US2b] Write unit tests in `test/features/expenses/domain/apply_proposal_test.dart` for `applyProposal(form, proposal)`.
  - An untouched form gets the title, items, project, category, supplier, date and payment status.
  - A user-edited project is kept while the supplier and payment status are filled (clarification Q3).
  - An existing typed item row is kept and the proposal items are appended after it.
  - A single untouched empty row is replaced, not appended to.
  - An edited title is kept.
  - Null proposal fields change nothing.
- [X] T051 [P] [US2b] Create the widget test `test/widget/paste_organize_sheet_test.dart`.
  - The Organize button is disabled for empty text and when offline, with `organizeOfflineHint` shown.
  - A progress indicator appears while running, and cancel closes the sheet without losing the text: reopening shows the same text.
  - A success result is popped to the caller.
  - An empty `items` result shows `organizeNoItemsFound` and keeps the sheet open with the text.
  - The AI disclosure dialog appears on first use when `VoiceAiDisclosureStore` is not yet accepted.

### Implementation

- [X] T052 [US2b] In `server/src/rpc/voice.ts`, add `organizeExpenseTextForUser(sql, deps, uid, data)`.
  - Validate `workspaceId` and call `assertCanMutateMoney`.
  - Trim `text` and check 1–4,000 chars.
  - Parse `currency`, `today` (`^\d{4}-\d{2}-\d{2}$`, else `cairoToday()`) and `languageHint`.
  - A missing API key gives `failed-precondition`.
  - Call `loadExtractionContext(sql, workspaceId)` and `extractReceipt`, and return `{text, proposal, source, needsConfirmation: true}`.

  Register it in `voiceRpcs` as `organizeExpenseText: {mutating: true, timeoutMs: 60_000, handler: …}`. Make T049 pass.
- [X] T053 [P] [US2b] Create `lib/features/expenses/data/expense_text_organizer.dart`. `ExpenseTextOrganizer.organize({workspaceId, text, currency})` calls `organizeExpenseText` through the existing `CallableClient`, the same way `voice_expense_repository.dart` calls `processVoiceExpense`, with an idempotency key per attempt. It sends `today` and returns `ExpenseProposal` plus `source`. Throw `CallableClientException` unchanged. Never enqueue offline. Add a Riverpod provider.
- [X] T054 [US2b] Implement `applyProposal` in `lib/features/expenses/domain/expense_proposal.dart`. It is a pure function over a small `ExpenseFormSnapshot` (title, titleEdited, projectId, projectEdited, category, categoryEdited, entityId, entityName, entityEdited, date, dateEdited, paymentStatus, paymentStatusEdited, items, itemsHaveUserEdits). It returns a new snapshot following research R7. The title comes from `proposal.proposedTitle` (T044), and is applied only when the title is untouched. Make T050 pass.
- [X] T055 [US2b] Create `lib/features/expenses/presentation/widgets/paste_organize_sheet.dart`.
  - A modal bottom sheet with a multiline `TextField` (max 4,000, key `qa_paste_text`), the "Organize with AI" button (key `qa_organize_ai`), a progress indicator with cancel, and inline errors.
  - Check `VoiceAiDisclosureStore` first and show the existing disclosure if it hasn't been accepted.
  - Disable the button offline, using the connectivity provider the offline queue already uses.
  - Keep the draft text in a provider so cancel or reopen restores it.
  - *Implemented as:* the disclosure dialog was extracted to `ensureAiDisclosureAccepted()` in `voice_ai_disclosure_store.dart` and is shared by the voice recorder and this sheet.

  Make T051 pass.
- [X] T056 [US2b] Wire it into `lib/features/expenses/presentation/screens/add_expense_screen.dart`.
  - Add a "Paste text" action (key `qa_add_expense_paste`) next to the title, hidden for the worker category.
  - On result, build an `ExpenseFormSnapshot` from the screen state. Track a `*Edited` flag per field and set it in each field's `onChanged`.
  - Call `applyProposal` and apply the result to the controllers and the `ExpenseItemsEditorController`.
  - Show the `multipleReceiptsWarning` and `statedTotalMismatch` info banners.
  - On save, set `inputMethod: 'text'`, `transcript` = the pasted text and `source` from the result.
  - Add a widget test group "paste + organize" to `test/widget/add_expense_screen_test.dart`, with a fake `ExpenseTextOrganizer` provider. A proposal with `multipleReceiptsSuspected: true` shows `multipleReceiptsWarning` on the add screen (Story 2b scenario 6). `totalMismatch: true` shows `statedTotalMismatch`. A pre-selected project is kept while supplier and payment status are filled.
- [X] T057 [US2b] Generalize the AI disclosure copy from voice-only to "voice and text" in both the `_en` and `_ar` disclosure strings in `lib/app/localization/app_localizations.dart`. Keep the storage key `voice_ai_disclosure_accepted` in `lib/features/voice_expense/data/voice_ai_disclosure_store.dart` unchanged, so acceptance stays shared.
- [ ] T058 [US2b] Run the quickstart §4 "Story 2b" checklist on a device.

**Checkpoint**: All stories work.

---

## Phase 9: Polish & Cross-Cutting

- [X] T059 [P] Check `lib/features/reports/services/report_export_data_builder.dart` (~lines 244 and 309) and `lib/features/reports/services/report_pdf_exporter.dart` (~line 322). Expense rows should show `expense.title` (falling back as before), with amounts unchanged. Run the existing report export tests to confirm the totals are identical. Item-level export stays out of scope.
  - *Result:* no change needed. Expense report rows use supplier, category and amount (never the description), and amount still equals the item sum. Report tests pass.
- [X] T060 [P] Update `README.md` (expense section) and `server/.env.example` comment, noting that `OPENROUTER_MODEL` also powers receipt organizing.
- [ ] T061 Final gate (constitution workflow): `cd server && npm run lint && npm test && npm run test:integration`, `npm run eval:receipts`, `flutter analyze 2>&1 | Select-Object -First 80`, `flutter test --reporter compact 2>&1 | Select-Object -Last 50`. Report every failure or skipped environment-dependent check.
  - *Status 2026-10-20:* server lint clean; unit 98/98; integration 118 pass, 0 fail (8 PowerSync sync-rule tests skipped: no PowerSync service locally, and sync rules are unchanged); flutter analyze clean; flutter test 787/787. **Pending:** `npm run eval:receipts`, which needs `OPENROUTER_API_KEY` (VPS only).
- [ ] T062 Release (quickstart §3).
  - Confirm that the 004 `cutover_at` is recorded in `ops/CUTOVER.md` and that 7 days have passed (research R12). **Contingency**: if 005 must ship earlier, first add `items` → Firestore `items` mapping in `server/tools/rollback-to-firestore/` with a test in `server/test/migration/rollback_mapping.test.ts`.
  - Take the totals snapshot (`SELECT project_id, sum(amount) FROM expenses WHERE NOT is_archived GROUP BY 1 ORDER BY 1` plus `SELECT count(*) FROM expenses`), run `ops/deploy.sh`, re-run both and require identical output.
  - Write `specs/005-multi-item-expenses/release-verification.md` with: date, migration applied (`007_expense_items`), both snapshots, the row counts, the comparison result (`mismatches: 0`), and the eval accuracy/latency from T061. This is the constitution Principle II record.
  - Bump the app version in `pubspec.yaml`. Install on both phones.
  - Run the quickstart §4 "Sync atomicity" check.
  - *Status 2026-10-20:* deployed to the VPS before the 004 cutover, as the owner chose (rollback mapping proven to carry items). Totals are identical (see `release-verification.md`). App version bump and phone installs are still pending.

---

## Dependencies & Execution Order

### Phase dependencies

```
Phase 1 Setup ──► Phase 2 Foundational ──┬─► Phase 3 US1 (MVP) ──► Phase 4 US3 ──┐
                                         ├─► Phase 5 US4 (after T013/T014) ──────┤
                                         └─► Phase 6 AI core ──┬─► Phase 7 US2 ───┤
                                                               └─► Phase 8 US2b ──┴─► Phase 9 Polish
```

- **US1** depends only on Phase 2.
- **US3** depends on US1's editor (T019) and screen wiring (T020).
- **US4** depends on Phase 2. T033 also touches files from T021/T023, so do it after them.
- **AI core (Phase 6)** depends only on Phase 2 (server side), so it can run in parallel with US1.
- **US2** depends on Phase 6 plus the editor T019. **US2b** depends on Phase 6, T019/T020 and T044
  (proposal model, from US2).
- **Release (T062)** depends on all of the above and on the external 004 cutover window.

### Within each phase

Tests are written first and fail. Then come models, services/RPC, UI, and a manual checklist last.

## Parallel Opportunities

- **Phase 1**: T002 ∥ T003.
- **Phase 2**: T004 ∥ T005 ∥ T011 ∥ T012. Then T006→T007→T008→T009→T010 (server chain) ∥
  T013→T014→T015→T016 (client chain).
- **After Phase 2**: one developer on US1 (T017–T025) while another does the AI core (T034–T040).
- **US1**: T017 ∥ T018. Then T019→T020. Then T021 ∥ T023. After that, T022 follows T021 (same file) and T024 follows T023 (same file).
- **US3**: T026, then T027→T028→T029→T030.
- **AI core**: T034 ∥ T035 ∥ T036 ∥ T039. Then T037→T038→T040.
- **US2**: T041 ∥ T042 ∥ T044. Then T043, then T045→T046→T047.
- **US2b**: T049 ∥ T050 ∥ T051 ∥ T053. Then T052, T054→T055→T056, then T057.
- **Polish**: T059 ∥ T060.

### Example: kick off US1 and the AI core together

```text
Dev A: T017 expense_items_editor_test.dart → T019 expense_items_editor.dart → T020 add_expense_screen.dart
Dev B: T034 receipt_extraction.test.ts + T039 receipts.jsonl → T037 receipt_extraction.service.ts → T040 eval
```

## Implementation Strategy

1. **MVP (manual only)**: Phases 1 → 2 → 3 → 4 → 5. That's multi-item receipts by hand, with editing and
   legacy safety, and no AI dependency. It can be released on its own (after the 004 window, T062).
2. **AI increment**: Phase 6, then Phase 7 (voice), then Phase 8 (paste). Each gets its own quickstart
   checklist and the eval gate.
3. **Polish + release**: Phase 9.

Stop at any checkpoint to validate that story independently. Commit after each task or logical group.

## Coverage map (spec → tasks)

| Requirement | Tasks |
|---|---|
| FR-001–005 structure, total = Σ, shared fields, order | T004–T010, T012–T013, T016, T019–T020, T022 |
| FR-006–009 manual entry, validation, title proposal, quick single item | T017–T020 |
| FR-010, FR-010a–c AI-first, fills mentioned fields, one proposal, paste option | T034–T037, T043, T050–T056 |
| FR-011–014 title words/numbers, order-free pairing, digits, currency words | T037, T039–T040 (eval) |
| FR-015–018 review before save, flags, mismatch, transcript kept | T042, T047, T051, T056 |
| FR-019 receipt files on the expense (at creation and later) | Existing attachments; verified T025, T030 |
| FR-020–022 list, detail, totals once | T021–T023, T008 (metrics), T059 |
| FR-023 legacy (incl. old queued edits) | T005, T010, T031–T033, T029 |
| FR-024 search title + items | T024 |
| FR-025 atomic sync | R1 design (single row); verified T062 |
| SC-001 timing (manual < 90 s, voice < 45 s) | T025, T048 (stopwatch steps) |
| SC-002–003 extraction quality, plan p95 ≤ 8 s | T039–T040 (accuracy + latency gate) |
| SC-004 totals unchanged + Principle II record | T031, T062 (`release-verification.md`) |
| SC-005–006 | T018, T062 |
