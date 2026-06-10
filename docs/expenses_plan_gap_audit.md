# Expenses & Organization Plan — Gap Audit & Implementation Log

Audit of the 20-section implementation plan against the existing BuildTrack (Flutter + Firebase) codebase, June 2026. The codebase already implemented the large majority of the plan in prior work. This document records the status of each section and the changes made in this pass.

## Status legend
- **Done** — already implemented and matches the plan.
- **Partial** — implemented but missing one or more acceptance items.
- **Added now** — implemented in this pass.
- **Open** — still to do.

## Section-by-section

| # | Section | Status | Notes |
|---|---------|--------|-------|
| 1 | Attachment system | Done (Partial) | `Attachment` model, validation, pending/upload services to Firebase Storage, `attachment_tile` with `InteractiveViewer` zoom, external open for PDF. Present on Expenses, Payments, and the shared Add-Entry form (contractor/transport/equipment). **Open:** worker *wage* entry screen (`add_worker_entry_screen`) has no attachment picker. |
| 2 | Separate + combined PDF export | **Added now** | Exporter already had project/entity/weekly/combined builders. **Added** per-section export: Expenses page, Payments page, and per-entity detail (see below). **Open:** dedicated "Build Custom PDF Report" screen with per-section checkboxes (combined export currently a single button). |
| 3 | Smart expense entry | Done | `add_expense_screen` has amount, category, currency, date, supplier, entity autocomplete, purpose, description, payment method, payment status, notes, attachments, edit-prefill. |
| 4 | Auto-save suppliers/workers | Done | `Entity` model + `entityRepository.ensureEntity` (trim/normalize, link-or-create), `entity_autocomplete_field`. |
| 5 | Automatic aggregation | Done (Partial) | `entityAggregationsProvider` + `EntitySummary`, list + detail screens. **Added now:** per-entity Export PDF on the detail screen. |
| 6 | Weekly summary | Done | `dashboardWeeklyInsights` + weekly PDF (`buildWeeklyInsightsReportPdf`). |
| 7 | Excel-like smart entry | Partial | Quick-add bottom sheet exists; grouped table-style views exist. **Open:** "Duplicate previous expense" and "use last category/method as default". |
| 8 | Organized expenses display | Done | `ExpenseGroupMode` switcher (date / relative date / category / entity / payment method), summary cards, search, filters. |
| 9 | Category grouping | Done | Group-by-category view with per-group totals/counts. |
| 10 | Filters & search | Done | `ExpenseFilter` covers every field in the spec; search bar + filter sheet. |
| 11 | Expense card UI | Done | Cards show entity, category, amount, date, status, method, attachment indicator. |
| 12 | Quick summary cards | Done | `expenseQuickSummary` (today / week / month / count). |
| 13 | Collapsible sections | Done | `expense_group_section` collapsible groups with header totals. |
| 14 | Navigation structure | Done (Partial) | Pages exist. **Open:** dedicated PDF Report Builder page (see §2). |
| 15 | DB/storage changes | Done | `expenses`, `payments`, `entities`, `categories`, `attachments` modelled; Firestore indexes/rules present. |
| 16 | Business logic rules | Done | Entity match (link-or-create), aggregation derived from transactions, shared filter logic. |
| 17 | PDF export service | **Added now** | `ReportPdfExporter` extended with `buildExpensesListPdf` and `buildPaymentsListPdf` (totals, category/method breakdown, detailed table, filters-applied line, attachment counts, Arabic Cairo fonts). |
| 18 | Phases | n/a | Plan phasing — informational. |
| 19 | Testing checklist | Open | No automated tests added for the new export paths yet. |
| 20 | Final acceptance | Mostly met | Remaining items listed under "Open" above. |

## Changes made in this pass

1. **`report_pdf_exporter.dart`** — added two methods:
   - `buildExpensesListPdf(...)` — title, project, date range, generated time, total + count, totals by category, totals by payment method, and a detailed expense table (date, category, entity, amount, method, status, attachment count). Honors a `filterSummary` string.
   - `buildPaymentsListPdf(...)` — equivalent for payments.
   - Added imports for `Expense` and `PaymentRecord`.
2. **`expenses_screen.dart`** — added an Export-PDF app-bar action + `_exportPdf()` that builds the PDF from `_filteredExpenses()` so the export matches exactly what is on screen (all active filters + search + date range), then shows it via `Printing.layoutPdf`.
3. **`payments_screen.dart`** — same Export-PDF app-bar action wired to `buildPaymentsListPdf` over `_filteredPayments()`.
4. **`entity_aggregation_detail_screen.dart`** — converted to `ConsumerWidget`; added an Export-PDF action that exports just that entity via the existing `buildEntitySummaryReportPdf`.
5. **`app_localizations.dart`** — added `dateRange` and `filtersApplied` keys (EN + AR). All other labels reused existing keys.

## Pass 2 — partials completed + remaining built

6. **§7 Duplicate expense** — added a "Duplicate" button on `expense_detail_screen` that copies all fields into a new expense (date set to today), handling subscription limits and offline-queue states like the add form.
7. **§7 Smart defaults** — new `expense_entry_defaults.dart` (`StateProvider<ExpenseEntryDefaults>`). `add_expense_screen` reads last category / payment method / payment status for new expenses and writes them back on save (session-scoped).
8. **§2/§14 Custom PDF Report builder** — new `buildCustomReportPdf` in the exporter (selective sections + date-range header). `reports_screen` got a "Build custom report" action opening a bottom sheet with date pickers + section checkboxes (Expenses, Payments, Weekly, Entity summary) → Generate PDF.
9. **§19 Tests** — new pure helpers `expense_totals.dart` (sum + category/method breakdowns), now used by the exporter so PDF totals can't drift from screen totals, plus `test/features/expenses/expense_totals_test.dart` asserting sums, grouping, and the "empty method → other" bucketing.

### §1 worker wage-entry attachments — finding
Worker spending with invoices/receipts already attaches through the **expense form** (category = Labor) and the shared add-entry "expense" tab. Only the payroll **wage-day** entry (`WorkerEntryRecord`, saved via a callable cloud function) lacks attachments. Adding them requires changing the cloud function + `WorkerEntryRecord`, which can't be deployed or verified in this environment — left as backend follow-up.

## Pass 3 — date-range-aware custom report

10. **§2 Range-aware custom report** — the custom builder no longer relies on the capped "recent 5" metrics. `_generateCustomReport` now pulls the full project lists via `expenseRepository.watchExpenses(...)` / `paymentRepository.watchPayments(...)` (`.first` snapshot), filters them by the selected date range (inclusive day boundaries), and passes the filtered lists to `buildCustomReportPdf`. The exporter computes the Expenses/Payments section totals + category/method breakdowns from those lists via the shared `expense_totals.dart` helpers, and lists every in-range row. So the totals shown in the custom PDF now reflect the chosen range, not just the latest few records.
    - Signature change: `buildCustomReportPdf` now takes `expenses: List<Expense>` and `payments: List<PaymentRecord>` instead of `metrics: ReportMetrics`.

## Pass 4 — worker wage attachments, domain screens, and report verification

11. **§1 Worker wage-entry attachments** — `WorkerEntryRecord`, worker-entry repository methods, offline mutation payloads, retry attachment ownership, the worker entry form, worker detail attachment tiles, and Cloud Functions create/update worker-entry handlers now preserve attachment metadata.
12. **§2 Daily report toggle** — the custom report builder includes a Daily toggle and derives daily rows from the bounded expense query.
13. **§19 Wider test coverage** — added worker wage-entry attachment tests, report request tests, report access tests, and PDF smoke tests for populated/empty custom reports.

## Still open (recommended next)

1. **External release verification** — run signed Android/iOS smoke tests for Google Sign-In, App Check, RevenueCat purchase/restore, offline queue drain, and PDF export on device.
2. **Firestore emulator verification** — run the emulator-backed rules/recompute suites with `FIRESTORE_EMULATOR_HOST` set before a production release.
3. **CI PDF font bundling** — PDF tests pass with Helvetica fallback when Cairo cannot be downloaded; bundling Cairo font assets would remove those warnings from offline CI.

## Verification note

The Flutter/Dart toolchain is **not available in this environment**, so these edits were **not compile-checked**. They closely follow existing, working patterns in the same files, but should be validated locally with:

```
flutter analyze
flutter test
```
