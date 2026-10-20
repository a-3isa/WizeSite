# Quickstart: Multi-Item Expenses: Develop & Verify

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## 1. Local development

The backend setup is the same as in feature 004 (`specs/004-vps-backend-migration/quickstart.md` §1).

```bash
cd server
docker compose -f compose.dev.yml up -d      # postgres + powersync
npm ci && npm run migrate                    # applies 007_expense_items.sql
npm run dev                                  # API on http://localhost:8080
npm test                                     # unit: item validation, receipt extraction post-processing (LLM stubbed)
npm run test:integration                     # Postgres: create/update with items, CHECK constraint, legacy payloads, organizeExpenseText
```

Flutter:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 --dart-define=SYNC_URL=http://10.0.2.2:8081
flutter analyze 2>&1 | Select-Object -First 80
flutter test --reporter compact 2>&1 | Select-Object -Last 50
```

## 2. AI extraction eval (manual, before any release that changes the prompt or model)

It needs a real `OPENROUTER_API_KEY` in `server/.env`. It costs a few cents per run.

```bash
cd server
npm run eval:receipts                        # reads test/eval/receipts.jsonl (≥ 20 cases)
```

Pass criteria (SC-002, SC-003):
- Reference case `فاتورة سباكه شهر 10 / 100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة` gives exactly the
  title `سباكه شهر 10` and the items `حنفية 100`, `جلبه 50`, `ماسورة 90`.
- Item exact-match accuracy (name + amount) is ≥ 85% across the set.
- **Zero** cases where a title number (`شهر 10`, `دور 3` …) became an item or amount.
- Reordered and chatter cases (items before title, extra greetings) pass at the same rate.
- Quantity case `2 حنفية بـ 200` gives name `حنفية`, quantity 2, amount 200.
- The printed AI latency is p95 ≤ 8 s (plan Performance Goals).

Record the result (model, date, accuracy) in the PR description.

## 3. Pre-deploy gate

- [ ] The 004 production cutover is done **and** its 7-day rollback window has closed
      (`ops/CUTOVER.md` has `cutover_at`, plus 7 days). Research R12.
- [ ] `npm test`, `npm run test:integration`, `flutter analyze`, `flutter test` all green.
- [ ] Eval (§2) passes.
- [ ] Totals snapshot taken: `SELECT project_id, sum(amount) FROM expenses WHERE NOT is_archived GROUP BY 1`
      saved before the migration.

Deploy: `ops/deploy.sh` (runs `npm run migrate`, then restarts the API). Rerun the totals snapshot
query. It must be **identical** to the pre-deploy snapshot (SC-004). Save both snapshots, the row
counts (`SELECT count(*) FROM expenses`) and the comparison result in
`specs/005-multi-item-expenses/release-verification.md`. This is the verification record that
constitution Principle II asks for. Install the new app build on both phones.

## 4. Manual verification checklist (on a device)

### Story 1: manual multi-item
- [ ] Add expense → title "سباكه شهر 10" → items حنفية 100, جلبه 50, ماسورة 90 → the total shows 240 live.
- [ ] Attach a receipt photo and a PDF → save → the list shows one row `سباكه شهر 10 · 3 items · 240`.
- [ ] The detail shows the three items on separate lines, the total 240, and both attachments open.
- [ ] Project total on the dashboard increased by exactly 240.
- [ ] A single-item expense (أسمنت 1,500) takes the same number of taps as before.
- [ ] Timing (SC-001): with a stopwatch, a 3-item receipt with title and photo takes < 90 s from tapping
      "Add expense" to the saved row. Record the time.
- [ ] Duplicate the 3-item expense from its detail screen → the copy has the same title, the same 3
      items and a total of 240.
- [ ] Empty title + items → save proposes the first item name as title.
- [ ] An item with an empty name or 0 amount blocks save and highlights the row.
- [ ] Worker category still shows the days × wage flow (no items editor).
- [ ] Equipment/transport entity with a default rate: one item → quantity × rate fills the amount.

### Story 2: voice
- [ ] Record the reference phrase → review shows the title and 3 items, total 240.
- [ ] Timing (SC-001): from tapping the mic to the saved row, including review and attaching the
      photo, takes < 45 s. Record the time.
- [ ] Record items first and the title last → same result.
- [ ] Record "…الإجمالي 250" with items summing to 240 → mismatch warning, saved total 240.
- [ ] Airplane mode during processing → transcript kept, manual entry possible.

### Story 2b: paste + Organize with AI
- [ ] Paste the reference text → Organize → form filled, total 240.
- [ ] Pick a project first, then paste text mentioning a supplier and "مدفوع" → the project is kept,
      and supplier and payment status are filled.
- [ ] Type one item manually, then Organize → the AI items are **appended** and the typed row is kept.
- [ ] Paste two receipts → "may contain more than one receipt" warning.
- [ ] Paste "hello" → "Couldn't find items" message, text kept.
- [ ] Offline → Organize disabled with a hint. Text kept.
- [ ] First use on a fresh install → AI disclosure shown once, and not shown again for voice.

### Story 3: edit
- [ ] Change the pipe to 95 and add تيفلون 10 → total 255 in the detail, list and project total.
- [ ] Reorder items → the order persists after reopening and on the second phone.
- [ ] Remove the last remaining item → blocked, with a suggestion to delete the expense.
- [ ] Open a saved expense, attach another receipt file, and save → both files show (FR-019 "later").- [ ] Edit the title → the new title shows on the second phone (this fixes the old "description not
      saved on update" bug).

### Story 4: legacy
- [ ] An expense created before the update opens as one item with its original amount. Its title is
      the old description, or the category name if that was empty.
- [ ] An offline expense queued on the **old** app build, synced after the update, saves correctly.
- [ ] Reports/exports for a past month show the same totals as before the update.

### Sync atomicity (FR-025, SC-006)
- [ ] Create a 10-item expense on phone A while phone B is open on the expenses list → B shows it with
      all 10 items in a single update, never partially.
