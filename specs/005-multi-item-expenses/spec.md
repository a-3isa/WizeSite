# Feature Specification: Multi-Item Expenses (One Receipt, Many Items)

**Feature Branch**: `005-multi-item-expenses`

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "i want to add feature or options for the expenses, i want that the expense can have more than one item and have one title, because the user will buy from the same workshop different items but all will have one reciept, also i want to take in mind that the user may rcord somthing like \"فاتورة سباكه شهر 10 \n100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة\" and so and so. i want the app then to understand that \"سباكه شهر 10\" is the tilte and every item should have its space, also the expense could have only one item, the user ofcourse can attach the reciept file"

## Clarifications

### Session 2026-10-19

- Q: Who extracts title and items from a voice recording — fixed word-order rules or AI? → A: AI is the primary extractor (people speak in different orders); it must not depend on a fixed phrasing order.
- Q: Should typed/pasted free text also be split automatically (was out of scope)? → A: Yes — the add-expense screen gets a "paste text" option with an "Organize with AI" button that splits the text into title, items and the other expense fields.
- Q: Which fields beyond title and items does the AI fill? → A: Title, items, project, category, supplier, date and payment status — only when mentioned in the recording/text, and never overwriting a field the user already set manually.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Record one receipt with several items manually (Priority: P1)

A site owner comes back from the plumbing workshop with one receipt that lists a faucet (100 EGP), a gasket (50 EGP) and a pipe (90 EGP). They open "Add expense", type a title such as "سباكه شهر 10", then add three item rows, each with its own name and amount. The app shows the running total (240 EGP) as they go. They pick the project, category, supplier and payment details once for the whole receipt, attach the receipt photo, and save. The expense list shows one entry titled "سباكه شهر 10" for 240 EGP; opening it shows the three items, each on its own line.

**Why this priority**: This is the core change: an expense stops being "one amount" and becomes "one receipt with its items". Every other story (voice understanding, editing, migration of old data) depends on this structure existing. On its own it already removes the user's current workaround of either creating three separate expenses for one receipt or cramming all items into the notes field.

**Independent Test**: Create an expense with a title and three items manually, attach a receipt file, save, then reopen it and confirm the title, the three items with their amounts, the total of 240 and the attached receipt are all shown correctly.

**Acceptance Scenarios**:

1. **Given** the user is on the add-expense screen, **When** they enter the title "سباكه شهر 10" and three items (حنفية 100, جلبه 50, ماسورة 90), **Then** the screen shows a total of 240 EGP before saving.
2. **Given** the expense from scenario 1 is saved, **When** the user opens it, **Then** they see the title, each item on its own line with its own amount, the total 240 EGP, and the shared project, category, supplier, date and payment details.
3. **Given** the user is adding an expense, **When** they enter a title and only one item (e.g. "أسمنت" 1,500 EGP), **Then** the expense saves with no extra steps compared with today's single-amount entry, and displays as one row with its title and a total of 1,500 EGP.
4. **Given** the user is adding an expense, **When** they attach one or more receipt files (photo or PDF), **Then** the files belong to the whole expense, not to a single item, and are viewable from the expense detail.
5. **Given** a multi-item expense is saved, **When** the user views project totals, category totals and reports, **Then** the expense contributes its full total (sum of items) exactly once.

---

### User Story 2 - Speak a receipt and let the app split title and items (Priority: P2)

Instead of typing, the user taps the voice button and says: "فاتورة سباكه شهر 10، 100 جنيه حنفية، 50 جنيه جلبه، 90 جنيه ماسورة". The app's AI reads the whole recording (not a fixed word-order pattern, because every person phrases a receipt differently) and understands that "سباكه شهر 10" is the title (dropping the filler word "فاتورة"), and that there are three items: حنفية 100, جلبه 50, ماسورة 90. It shows a review screen with the title and each item in its own editable row, plus the total of 240. The user corrects anything wrong, adds the receipt photo, and saves.

**Why this priority**: The user explicitly called out this way of recording. It turns a 1–2 minute typing task into a few seconds of speaking, which is the main value of the app's existing voice entry. It depends on Story 1's structure, so it comes second.

**Independent Test**: Record (or feed the recognizer) the example phrase and confirm the review screen proposes the title "سباكه شهر 10" and exactly three items with the right names and amounts, without "10" from "شهر 10" being turned into an item or an amount.

**Acceptance Scenarios**:

1. **Given** the user records "فاتورة سباكه شهر 10 ... 100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة", **When** the app finishes understanding it, **Then** the review screen shows title "سباكه شهر 10" and three items: حنفية 100, جلبه 50, ماسورة 90, total 240.
2. **Given** the recording contains a number that is part of the title (e.g. "شهر 10", "دور 3", "شقة 5"), **When** the app understands it, **Then** that number stays in the title and is not treated as an item amount.
3. **Given** the user says the amount after the item name (e.g. "حنفية بـ 100، جلبه 50 جنيه"), or says the items first and the title last (e.g. "حنفية 100 وجلبه 50 وماسورة 90، دي فاتورة السباكة بتاعة شهر 10"), **When** the app understands it, **Then** the same title and the same name–amount pairs are proposed regardless of the order spoken.
4. **Given** the user records a single item (e.g. "رمل 2000 جنيه"), **When** the app understands it, **Then** the review screen shows one item and proposes a title from the item (e.g. "رمل") that the user can change.
5. **Given** the app is unsure about any item (no amount heard, or an amount with no name), **When** the review screen opens, **Then** that row is visibly flagged for the user to complete, and the expense cannot be saved until every item has a name and a positive amount.
6. **Given** the user also says a grand total (e.g. "الإجمالي 240") and it differs from the sum of the items, **When** the review screen opens, **Then** the app shows both numbers and warns about the mismatch; the saved total is always the sum of the items.

---

### User Story 2b - Paste receipt text and "Organize with AI" (Priority: P2)

The user already has the receipt as text (a WhatsApp message from the workshop, a note they typed earlier). On the add-expense screen they choose "Paste text", paste the whole text, and tap "Organize with AI". The AI splits it into a title and items and fills project, category, supplier, date and payment status when the text mentions them, leaving any field the user already filled untouched. The same editable review appears as for voice; the user checks it, attaches the receipt file, and saves.

**Why this priority**: Same value as voice for users who receive receipts as messages; reuses the same AI understanding and review step.

**Independent Test**: Paste the reference text "فاتورة سباكه شهر 10\n100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة", tap "Organize with AI", and confirm the form is filled with title "سباكه شهر 10" and the three items, ready to review.

**Acceptance Scenarios**:

1. **Given** the user is on the add-expense screen, **When** they open "Paste text", paste the reference text and tap "Organize with AI", **Then** the title and the three items are filled into the form for review, total 240.
2. **Given** the pasted text is in any order or layout (one item per line, all on one line, items before title, extra chatter like "تمام يا باشا"), **When** the user taps "Organize with AI", **Then** the title and items are extracted correctly and the irrelevant words are ignored.
3. **Given** the AI cannot find any item with an amount in the pasted text, **When** organizing finishes, **Then** the user sees a clear message, the pasted text is kept, and they can enter items manually.
4. **Given** organizing is running, **When** the user waits, **Then** they see a progress indicator and can cancel without losing the pasted text.
5. **Given** the user already picked a project and the pasted text mentions a different supplier and "مدفوع", **When** they tap "Organize with AI", **Then** the supplier and payment status are filled from the text and the user's chosen project is kept.
6. **Given** the pasted text contains what looks like two separate receipts, **When** organizing finishes, **Then** the app creates one expense proposal and warns that the text may hold more than one receipt, so the user can split it manually.

---

### User Story 3 - Edit items of an existing expense (Priority: P2)

After saving, the user notices the pipe was actually 95 EGP and one more item (شريط تيفلون 10 EGP) was on the receipt. They open the expense, edit the pipe amount, add the new item, and save. The total updates to 255 everywhere.

**Why this priority**: Receipts are often recorded quickly on site and corrected later. Without editing, a single mistake forces deleting and re-entering the whole receipt.

**Independent Test**: Open a saved three-item expense, change one amount, add one item, remove another, save, and confirm the detail screen, expense list and project totals all reflect the new total.

**Acceptance Scenarios**:

1. **Given** a saved multi-item expense, **When** the user changes an item amount and saves, **Then** the expense total and all totals that include it update accordingly.
2. **Given** a saved multi-item expense, **When** the user adds or removes items and saves, **Then** the item list and total reflect the change.
3. **Given** an expense with exactly one item, **When** the user tries to remove that last item, **Then** the app prevents it (an expense always has at least one item) and suggests deleting the whole expense instead.
4. **Given** the user reorders items, **When** they save and reopen the expense, **Then** the items appear in the order the user set.

---

### User Story 4 - Existing expenses keep working (Priority: P3)

Expenses recorded before this feature (one amount, a description/notes) keep appearing with the same amount in all lists, totals and reports. When opened, each shows as an expense with one item whose amount is the original amount, and a title taken from its existing description (or its notes when there is no description, or its category when both are empty).

**Why this priority**: Required for correctness of historical totals, but involves no new user workflow.

**Independent Test**: With expenses created before the change present, confirm every project total and report figure is unchanged after the feature ships, and that opening an old expense shows a sensible title and one item.

**Acceptance Scenarios**:

1. **Given** an expense created before this feature, **When** the user opens it, **Then** it shows a title and one item with the original amount, and the original notes are preserved.
2. **Given** expenses created before this feature, **When** project, category and report totals are calculated, **Then** they equal the totals shown before the feature shipped.

---

### Edge Cases

- **Title-only recording**: user says "فاتورة سباكه" with no amounts → review screen opens with the title and one empty, flagged item row; cannot save until an item has a name and amount.
- **Amounts with no names**: "100 و 50 و 90" → three items with amounts but flagged empty names.
- **Arabic-Indic digits and spoken numbers**: "١٠٠ جنيه" and "مية وخمسين جنيه" are understood as 100 and 150.
- **Quantities inside the item**: "2 حنفية بـ 200" → one item named "حنفية" with quantity 2 and amount 200 (the stated amount is the line total; the app never multiplies amount by quantity).
- **Duplicate item names**: two rows "حنفية 100" and "حنفية 100" are both kept as separate items.
- **Zero or negative amounts**: not allowed for an item; row is flagged.
- **Very long receipts**: an expense with many items (e.g. 30+) stays usable — the list scrolls and the total remains visible.
- **No title given manually**: if the user leaves the title empty, the app proposes one (first item name, or category) rather than blocking the save.
- **Mixed currencies**: all items of one expense share the expense currency; a different currency word on one item is flagged for the user.
- **Offline**: a multi-item expense created offline saves locally with all its items and receipt, and syncs as one unit; no partial expense (some items missing) ever appears on another device.
- **AI understanding fails or is unavailable** (no network, AI service error or timeout): the user keeps the transcript or pasted text and can fill the title and items manually on the same screen; nothing already entered is lost.

## Requirements *(mandatory)*

### Functional Requirements

**Structure**

- **FR-001**: An expense MUST have exactly one title and one or more items.
- **FR-002**: Each item MUST have a name and a positive amount; it MAY have an optional quantity and an optional note.
- **FR-003**: The expense total MUST always equal the sum of its item amounts; the user MUST NOT be able to enter a total that differs from that sum.
- **FR-004**: Project, category (for the whole expense), supplier/entity, date, currency, payment method, payment status and receipt attachments MUST be set once per expense and apply to all its items.
- **FR-005**: Items MUST keep the order in which the user entered or arranged them.

**Manual entry & editing**

- **FR-006**: Users MUST be able to add, edit, remove and reorder items while creating or editing an expense, with the total updating live.
- **FR-007**: The app MUST prevent saving an expense with zero items, or with any item missing a name or a positive amount, and MUST point the user to the incomplete row.
- **FR-008**: When the title is left empty, the app MUST propose a title (first item name, or category name if no item name) that the user can accept or change.
- **FR-009**: A single-item expense MUST be as quick to enter as today's single-amount expense (no extra mandatory steps beyond today's fields).

**AI understanding (voice and pasted text)**

- **FR-010**: When the user records an expense by voice, or pastes text and taps "Organize with AI", the app MUST use AI as the primary extractor to propose a title and a list of items (name + amount each). Extraction MUST NOT depend on a fixed word or line order; FR-011 to FR-018 apply equally to voice and pasted text.
- **FR-010a**: Besides title and items, the AI MUST propose project, category, supplier/entity, date and payment status when (and only when) the recording or text mentions them; fields not mentioned keep their current or default values, and the AI MUST NOT overwrite any field the user already set manually.
- **FR-010b**: One "Organize with AI" run or one recording MUST produce exactly one expense proposal; if the input appears to contain more than one receipt, the app MUST warn the user.
- **FR-010c**: The add-expense screen MUST offer a "Paste text" option with an "Organize with AI" button; the pasted text MUST be kept until the user saves or discards the expense.
- **FR-011**: The app MUST drop leading filler words that only describe the document (e.g. "فاتورة", "بون", "وصل", "إيصال") from the proposed title.
- **FR-012**: Numbers that are part of the title phrase (e.g. "شهر 10", "دور 3") MUST stay in the title and MUST NOT become item amounts.
- **FR-013**: The app MUST pair each amount with its item name whether the amount is said before ("100 جنيه حنفية") or after ("حنفية بـ 100") the name, and MUST understand Western digits, Arabic-Indic digits and spoken Egyptian Arabic numbers up to the millions (e.g. "مية وخمسين" = 150, "ألف وميتين" = 1,200), as covered by the receipt evaluation set.
- **FR-014**: The app MUST treat currency words ("جنيه", "ج", "EGP") as currency, not as part of an item name.
- **FR-015**: Every AI proposal MUST be shown on an editable review screen before saving; nothing is saved without the user's confirmation.
- **FR-016**: Items the app is unsure about MUST be visibly flagged on the review screen.
- **FR-017**: If a spoken grand total differs from the sum of the items, the app MUST show both and warn the user; the saved total MUST be the sum of the items.
- **FR-018**: The original transcript or pasted text MUST be kept with the expense so the user can compare it with the proposed items.

**Receipt**

- **FR-019**: Users MUST be able to attach one or more receipt files (photo or PDF) to an expense, from camera, gallery or files, both during creation and later; receipt files belong to the expense as a whole.

**Display, totals & history**

- **FR-020**: Expense lists MUST show one row per expense with its title, total and item count (when more than one item).
- **FR-021**: The expense detail MUST show every item on its own line with its own amount, followed by the total.
- **FR-022**: All totals, budgets, summaries and reports that use expenses MUST use the expense total, counting each expense once.
- **FR-023**: Expenses recorded before this feature MUST appear as one-item expenses with their original amount, a title derived from their existing description (falling back to notes, then to the category when both are empty), and their original notes preserved; no historical total may change.
- **FR-024**: Searching or filtering expenses by text MUST match the title and item names.
- **FR-025**: A multi-item expense MUST be created, edited and synced as one unit: other devices see either the whole expense with all its items or nothing.

### Key Entities

- **Expense (receipt)**: One purchase event backed by one receipt. Has a title, project, category, supplier/entity, date, currency, payment method and status, optional notes, the original voice transcript (when recorded by voice), receipt attachments, and an ordered list of items. Its total is the sum of its items.
- **Expense Item**: One line on the receipt. Belongs to exactly one expense. Has a name, an amount, an optional quantity, an optional note, and its position in the list.
- **Receipt Attachment**: A photo or PDF of the receipt, attached to the expense as a whole (existing attachment concept, unchanged).
- **AI Proposal**: The app's understanding of a recording or pasted text — proposed title, proposed items, any spoken grand total, and per-item flags for uncertain rows — shown for review and discarded once the user saves or cancels.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can record a 3-item receipt (title, three items, receipt photo) manually in under 90 seconds, and by voice in under 45 seconds including review.
- **SC-002**: For the reference phrase "فاتورة سباكه شهر 10، 100 جنيه حنفية، 50 جنيه جلبه، 90 جنيه ماسورة", the voice proposal gives the exact title "سباكه شهر 10" and the exact three items with correct amounts.
- **SC-003**: Across a test set of at least 20 realistic Egyptian-Arabic receipts (recordings and pasted texts, 1–8 items each, in varied word and line orders), at least 85% of items are proposed with the correct name and amount without user correction, and no title number (e.g. "شهر 10") is ever turned into an item.
- **SC-004**: After release, 100% of project and report totals that existed before the feature are unchanged.
- **SC-005**: Recording a single-item expense takes no more taps than it does today.
- **SC-006**: Zero cases where another device shows a multi-item expense with only some of its items.

## Assumptions

- **Category is per expense**, not per item: one receipt from one workshop is one kind of cost (e.g. plumbing). Users who need separate categories record separate expenses.
- **Item fields are name + amount** (amount = line total for that item). Quantity and unit are optional and informational only; the app does not compute amount from quantity × unit price in this version.
- **Voice and pasted text share one AI understanding step** and one review screen; the existing voice-expense flow is extended rather than duplicated.
- **Reading items from the receipt photo (OCR)** is out of scope; the photo is stored as proof only.
- **Item-level reports** (e.g. "how much did we spend on pipes across all projects") are out of scope; reports work at expense level. Item names are searchable (FR-024).
- **Currency** defaults to the workspace currency (EGP for current users); one currency per expense.
- **Only two installs exist** (owner + one other user), so no backward-compatibility work for old app versions reading new multi-item data is required; all installs will update together. Existing stored expenses must still be read correctly (FR-023).
- Existing permissions, offline behaviour, attachment upload and sync rules for expenses apply unchanged to multi-item expenses.
