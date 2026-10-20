# Implementation Plan: Multi-Item Expenses (One Receipt, Many Items)

**Branch**: `005-multi-item-expenses` | **Date**: 2026-10-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-multi-item-expenses/spec.md`

## Summary

An expense becomes **one receipt with a title and 1–100 line items**. The total stays in
`expenses.amount` and always equals the item sum. The user can enter items by hand, by voice, or by
pasting text and tapping **"Organize with AI"**. In both AI paths, one structured LLM call extracts the
title, items and any mentioned project, category, supplier, date or payment status, whatever the word
order. The user then reviews and saves.

Technical approach:

1. **Items live on the expense row** as an ordered `items JSONB` column (like `attachments`). The
   expense and its items are always written and synced as one row (FR-025). The existing `amount`
   column, every recompute/summary/report and the sync rules stay untouched (FR-022, SC-004). A
   Postgres CHECK plus RPC validation enforce `amount = Σ items`.
2. **No backfill.** Legacy rows have `items = []` and get a deterministic single virtual item on read.
   RPC payloads without `items` behave exactly as today, so old offline-queue entries replay.
3. **The existing `description` field is the title.** It is relabelled in the UI, shown everywhere
   already, and now persisted by `updateExpense` (a latent bug).
4. **AI-first extraction**: a new `receipt_extraction.service.ts` (OpenRouter, strict JSON schema)
   serves `processVoiceExpense` (additive `proposal` field) and the new `organizeExpenseText` RPC. The
   existing rules extractor becomes the fallback when the AI fails.
5. **Client**: a reusable `ExpenseItemsEditor` widget (add, voice review), a `PasteOrganizeSheet`, and an
   `applyProposal` merge that fills only untouched fields and appends items (clarification Q3).

## Technical Context

**Language/Version**: Dart 3 / Flutter (client); TypeScript on Node.js 22 (server)

**Primary Dependencies**: Unchanged. Server: Fastify, postgres.js, node-pg-migrate, OpenRouter via
`fetch`. Client: `powersync`, Riverpod, existing `CallableClient` and Hive offline queue. **No new
packages.**

**Storage**: PostgreSQL 17 `expenses.items JSONB` (migration 007); device SQLite replica gets an
`items` text column; attachments unchanged (VPS file store)

**Testing**: `node --test` unit tests (item validation, extraction post-processing with LLM stubbed);
Postgres integration tests (create/update with items, CHECK constraint, legacy payloads,
`organizeExpenseText`); `flutter test` (model parsing, legacy fallback, `applyProposal`, items editor
widget, add/voice-review screens); manual live-AI eval `npm run eval:receipts` (≥ 20 cases, ≥ 85%);
manual checklist in [quickstart.md](./quickstart.md)

**Target Platform**: Android + iOS client; single Linux VPS (Docker Compose) server

**Project Type**: Mobile app + self-hosted API/sync backend

**Performance Goals**: Organize/voice extraction p95 ≤ 8 s end-to-end (one LLM call, 20 s hard
timeout → rules fallback); items editor stays smooth at 100 rows; SC-001 (3-item receipt < 90 s
manual, < 45 s voice)

**Constraints**: Additive contract only (constitution I); totals unchanged (SC-004); the AI never
overwrites manual input; Arabic/RTL; paste is online-only; text ≤ 4,000 chars; deploy only after
the 004 cutover + 7-day rollback window (research R12)

**Scale/Scope**: 2 users. ~1 migration, 3 changed RPCs (create, update, processVoiceExpense), 1 new RPC, 1 new domain service; client: 1
model, 2 new widgets, 3 changed screens (add, detail, voice review), list row, 2 search sites, sync
schema

**Unknowns**: None. All resolved in [research.md](./research.md) (R1–R12).

## Constitution Check

*GATE: evaluated before Phase 0 and re-evaluated after Phase 1 design.* Constitution **2.0.0**.

| Principle / Constraint | Status | How the plan complies |
|---|---|---|
| **I. Preserve Existing Product Behavior** | ✅ | Additive RPC fields only. Payloads without `items` behave as today. `processVoiceExpense` keeps all old response fields. Rules extractor is kept as fallback. Worker-entry and resource-rate flows are kept. |
| **II. Accounting Correctness & Traceability** | ✅ | `amount` stays the single total read by recompute. `amount = Σ items` enforced in the RPC (piastre arithmetic) **and** a Postgres CHECK. Legacy rows load with a deterministic fallback. No money values migrated, so no verification report is needed. A pre/post totals snapshot is taken anyway (quickstart §3). |
| **III. Test-Backed Change Discipline** | ✅ | Unit + integration tests for validation, CHECK, legacy payloads and extraction post-processing. Flutter tests for parsing, fallback, merge and editor. Live AI quality is covered by a versioned eval set plus a manual checklist (it can't be deterministic in CI). |
| **IV. Offline, Security & Recovery First** | ✅ | Manual create/edit stays offline-queued with `clientMutationId`. Organize is online-only with a visible disabled state, and text is kept. `organizeExpenseText` requires `assertCanMutateMoney`. Items sync in the same `workspace_member` bucket as their expense (no new exposure). Raw text is never logged. The AI disclosure is reused. Covered by existing backups. |
| **V. Scalable Data Access** | ✅ | No new queries. Items ride on rows already paginated. Item cap is 100. Search stays in the existing in-memory filter over the already-loaded page. |
| Metadata-only records / file store holds files | ✅ | Receipts use the existing attachment flow. Items hold no files. |
| Backend-enforced integrity | ✅ | RPC validation + CHECK constraints (array, ≤ 100, sum). |
| Indexes only for implemented queries | ✅ | None added. |
| Reproducible deploy; secrets out of repo/bundle | ✅ | SQL migration via `ops/deploy.sh`. Reuses `OPENROUTER_API_KEY` from the server `.env`. |
| Workflow gate: analyze + tests + backend tests | ✅ | quickstart §1 and §3. |

**Gate result: PASS.** No violations.

**Post-design re-check (after Phase 1)**: data model (JSONB + CHECK, no backfill), contracts (additive)
and quickstart introduce no violations. One sequencing dependency on feature 004 is recorded (R12),
and it is not a violation. **PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/005-multi-item-expenses/
├── plan.md                    # This file
├── research.md                # Phase 0: decisions R1–R12
├── data-model.md              # Phase 1: expenses.items, ExpenseItem, legacy fallback, AI Proposal
├── quickstart.md              # Phase 1: dev, eval, pre-deploy gate, manual checklist
├── contracts/
│   ├── rpc-expense-items.md   # createExpenseWithQuota / updateExpense / organizeExpenseText / processVoiceExpense
│   └── ai-extraction.md       # prompt rules, strict JSON schema, post-processing, fallback
├── checklists/requirements.md
└── tasks.md                   # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
server/
├── migrations/007_expense_items.sql              # NEW: items column, expense_items_total(), CHECKs
├── src/rpc/
│   ├── expenses.ts                               # items validation + total; persist description on update; inputMethod 'text'
│   ├── expense_items.ts                          # NEW: parseItems(), piastre sum (pure, unit-tested)
│   └── voice.ts                                  # call receipt extraction; add `proposal`; organizeExpenseText (registered via voiceRpcs, already spread in registry.ts)
├── src/domain/voice/
│   ├── services/receipt_extraction.service.ts    # NEW: one LLM call → proposal; rules fallback
│   ├── services/entity_matcher.service.ts        # NEW: supplier name → entity id (mirrors project_matcher)
│   ├── services/expense_parser.service.ts        # kept for the rules fallback path
│   └── types/expense.ts                          # ExpenseProposal types
└── test/
    ├── unit/expense_items.test.ts                # NEW
    ├── unit/voice/receipt_extraction.test.ts     # NEW (LLM stubbed)
    ├── integration/expenses_payments.test.ts     # extend: items, CHECK, legacy payload, description update
    ├── integration/voice.test.ts                 # extend: proposal field, organizeExpenseText
    └── eval/receipts.jsonl + eval_receipts.ts    # NEW: live AI eval (npm run eval:receipts)

lib/
├── core/sync/schema.dart                         # + Column.text('items')
├── core/sync/local_row.dart                      # + 'items' in _jsonColumns
├── core/services/workspace_mutation_service.dart # createManualExpense/updateExpense: + items, title
├── core/services/expense_save_service.dart       # voice save: items + inputMethod
├── features/expenses/
│   ├── domain/expense_item.dart                  # NEW
│   ├── domain/expense.dart                       # + items, effectiveItems, title
│   ├── domain/expense_proposal.dart              # NEW: proposal model + applyProposal()
│   ├── data/expense_repository.dart              # createExpense/updateExpense + items param (abstract + impl); offline overlay; search title + item names
│   ├── data/expense_text_organizer.dart          # NEW: calls organizeExpenseText
│   └── presentation/
│       ├── widgets/expense_items_editor.dart     # NEW: rows, reorder, live total, flags, validation
│       ├── widgets/paste_organize_sheet.dart     # NEW: paste + Organize with AI
│       ├── screens/add_expense_screen.dart       # title on top; items editor; paste entry point
│       ├── screens/expense_detail_screen.dart    # items section; duplicate action copies items + title
│       └── screens/expenses_screen.dart          # row: "title · N items"; search includes items
├── features/voice_expense/
│   ├── domain/voice_expense_models.dart          # + proposal
│   └── presentation/screens/voice_review_screen.dart  # items editor instead of single amount
└── app/localization/app_localizations.dart       # new _en/_ar keys (title, items, organize, warnings)

test/
├── features/expenses/expense_item_test.dart      # NEW: parsing, legacy fallback
├── features/expenses/apply_proposal_test.dart    # NEW: no-overwrite, append
├── widget/expense_items_editor_test.dart         # NEW
├── widget/add_expense_screen_test.dart           # extend
├── widget/expenses_screen_filter_test.dart       # extend: search matches item names
└── widget/voice_review_screen_test.dart          # extend
```

**Structure Decision**: Keep the existing layout (`server/` from 004, Flutter feature folders). The
voice domain folder hosts the shared receipt extractor because it already owns the transcription,
normalization and matching utilities. No new top-level directories. `functions/` (frozen
Firebase code) is **not** changed.

## Delivery slices (for `/speckit-tasks`)

| # | Slice | Maps to | Exit gate |
|---|---|---|---|
| 0 | Baseline green: `npm test`, `npm run test:integration`, `flutter analyze`, `flutter test` | Constitution | All green before changes |
| 1 | **Server data + RPC**: migration 007, `expense_items.ts`, create/update with items, description persisted on update, `inputMethod: text` | US1, US3, US4; FR-001–005, 023, 025 | Unit + integration green; legacy payload test green |
| 2 | **Client model + sync**: schema column, `_jsonColumns`, `ExpenseItem`, `effectiveItems`, offline overlay with items | US1, US4; FR-023 | Flutter tests green; old queued payload test |
| 3 | **Items editor + manual flow**: editor widget, add/edit screen, detail, list row, search, title proposal | US1, US3 (**MVP**) | Widget tests; quickstart Story 1 + 3 |
| 4 | **AI extraction service**: `receipt_extraction.service.ts`, entity matcher, rules fallback, eval set + script | US2, US2b; FR-010–018 | Unit tests (stubbed); `eval:receipts` ≥ 85%, 0 title-number errors |
| 5 | **Voice integration**: `processVoiceExpense.proposal`, voice review with items editor | US2 | Integration + widget tests; quickstart Story 2 |
| 6 | **Paste + Organize**: `organizeExpenseText` RPC, `PasteOrganizeSheet`, `applyProposal`, disclosure copy | US2b; FR-010a–c | Integration + `applyProposal` tests; quickstart Story 2b |
| 7 | **Release**: pre-deploy gate (004 window closed), totals snapshot before/after, deploy, both phones updated | SC-004, SC-006 | Snapshot identical; quickstart sync check |

Slices 1–3 are a shippable MVP: multi-item by hand, with no AI dependency. Slices 4–6 add the AI
paths.

## Complexity Tracking

No constitution violations to justify.
