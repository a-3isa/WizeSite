# Buildozer — UI/UX Reconstruction Proposal

Status: **proposal for review** (nothing in this doc is implemented except where marked ✅ DONE).
Scope: dropdown/filter cleanup, number formatting, data-model duplicate audit, dashboard redesign, and a full-app information-architecture reconstruction.

---

## 0. Already shipped this session ✅ DONE

- **Thousands separators while typing.** New `ThousandsSeparatorInputFormatter` groups the integer part live (`1000000` → `1,000,000`) on the expense and payment amount fields, including pre-filled/edit values. `NumberParser` now distinguishes a grouping comma (`1,000` → 1000) from a decimal comma (`1,5` → 1.5) and an Arabic separator. Covered by `test/core/utils/number_parser_test.dart`.
- **iOS Google sign-in fix** (earlier): explicit `clientId` on Apple platforms.

Remaining work below is **not** started — it needs your direction first.

---

## 1. Data-model duplicate audit (the "worker = labor" class of bug)

The root cause is overlapping enum values that render with near-identical labels. Found:

| # | Where | Duplicate | Reality | Risk if naively merged |
|---|-------|-----------|---------|------------------------|
| 1 | `AccountingCategories` | `worker` vs `labor` | **Not** the same. `worker` (new expense) routes to `_saveWorkerEntry` — the daily-wage worker-day flow (days × wage). `labor` is a plain expense line. | Deleting `labor` or `worker` breaks the worker-entry shortcut or existing labor expenses. |
| 2 | `AccountingEntityTypes` | `supplier` vs `vendor` | `_entityTypeLabel` maps **both** to `t('supplier')`. The entity-type filter therefore shows "Supplier" **twice**. Pure duplication. | Low — `vendor` looks like dead/legacy alias of `supplier`. |
| 3 | `AccountingCategories` | `payments` as a category | "Payments" as an *expense category* is conceptually odd next to the Payments feature. Likely legacy. | Medium — may be referenced by old records. |
| 4 | Arabic strings | `expenseCategoryWorker`, `expenseCategoryContractor` | Arabic values are still English ("Worker"/"Contractor"), unlike `expenseCategoryLabor` = "عمالة". | None — translation gap. |

### Recommendation
1. **worker/labor** — do **not** merge. Disambiguate labels instead:
   - `worker` → "Worker (daily wage)" / "عامل (أجر يومي)"
   - `labor` → "Labor (lump sum)" / "عمالة (مبلغ مقطوع)"
   Plus a one-line helper under the picker explaining the wage flow. If you confirm `labor` is genuinely unused, we can instead **deprecate** it (hide from picker, keep parsing old records).
2. **supplier/vendor** — collapse: drop `vendor` from the filter `values` list, keep it only for backward-compatible reads, and map legacy `vendor` records to `supplier` on display. Removes the double "Supplier".
3. **payments category** — confirm usage in Firestore, then hide from the picker if legacy.
4. Fill the missing Arabic translations.

> Need your call on #1 (relabel vs deprecate `labor`) and confirmation on #2/#3 before I touch the enums, since these are persisted values.

---

## 2. Filters / dropdowns — dedupe & refine

**Problem you flagged ("interferes with payments").** `expenses_screen.dart` and `payments_screen.dart` each hand-build the *same* `BelowDropdownField` filters inline (payment method, payment status, entity type) **plus** their own copy of `_entityTypeLabel`, active-filter chips, and clear logic. They drift independently — that's the interference.

**Proposed refactor (low risk, no behavior change):** extract shared widgets to `lib/features/common/presentation/widgets/filters/`:

- `PaymentMethodFilterField`
- `PaymentStatusFilterField`
- `EntityTypeFilterField`  ← single source, fixes the supplier/vendor double-listing in one place
- `CategoryFilterField` (expenses only)
- shared `entityTypeLabel(l10n, type)` helper (move out of both screens)

Both screens then compose these instead of copy-pasting. ~150 duplicated lines removed; future option changes happen once.

---

## 3. Dashboard redesign (currently "very crowded")

### Why it feels crowded
`dashboard_screen.dart` is one long `ListView` with large 24px gaps stacking, top-to-bottom:
1. Sync/queue banner
2. **Resources** nav grid (4 directory cards) ← navigation, not data
3. **Overview** financial grid (4 cards, aspect 1.35 → tall)
4. **Weekly summary** (2 more cards, repeats Expenses/Income labels)
5. Upgrade card

So 6 financial cards + 4 nav cards + banners — and the *navigation* shortcuts sit **above** the financial data that is the screen's actual purpose. Expenses/Income labels appear twice (totals vs weekly), which reads as repetition.

### Proposed layout (financial-first, denser)
```
┌─────────────────────────────────────────┐
│ Workspace ▾                  🔔  ⚙        │
├─────────────────────────────────────────┤
│ [ sync banner — only when pending ]      │
│                                          │
│  Net this month        ▲ 124,500 EGP     │  ← single hero card,
│  Income 320,000   Expenses 195,500       │     profit/loss colored
│                                          │
│  ┌─ This week ──────── [Month ▾] ──┐     │  ← segmented period toggle
│  │ Income 40,000   Expenses 22,300 │     │     replaces separate
│  └─────────────────────────────────┘     │     Weekly section
│                                          │
│  Active projects  7      Top: Materials  │  ← compact stat row
│                                          │
│  Quick access                            │  ← Resources demoted,
│  [Workers][Contractors][Equip][Transp.]  │     single scrollable row
│                                          │
│  [ Upgrade to Pro — free tier only ]     │
└─────────────────────────────────────────┘
```
Changes: one hero net card (not a 2×2 grid), a period **segment** that swaps week/month instead of a duplicate section, a compact stat line, and Resources demoted to a single horizontal "Quick access" strip below the data. Tighten gaps 24→16.

**Risk:** medium — restructures one screen, reuses existing `MetricCard`/providers. No data changes.

---

## 4. Full-app IA reconstruction (optional, larger)

Today's bottom nav is 3 tabs: **Home · Add(menu) · Projects**. Expenses, Payments, Workers, Reports, Settings are all `push` routes with no home in the nav — discoverability depends on the dashboard Resources grid and project drill-downs. Two list screens (expenses/payments) duplicate ~80% of their filter/group/list code.

### Proposed structure
1. **Nav: Home · Activity · Add · Projects · More.**
   - **Activity** = unified Expenses + Payments ledger with a type toggle (kills the two near-identical screens and the filter duplication from §2 by construction).
   - **More** = Workers, Reports, Directories, Settings (replaces the dashboard Resources grid; dashboard becomes data-only per §3).
2. **One shared "transactions list" component** parameterized by type, used by Activity and by project drill-downs.
3. **Consistent entry forms**: add-expense and add-payment share field layout, the new amount formatter, and the shared filter/entity widgets.
4. **Design tokens pass**: standardize spacing scale (4/8/12/16/24), card radius, and the metric-card aspect ratio app-wide so density is uniform.

This is a multi-PR effort. I'd sequence it: §2 (safe dedupe) → §1 (enum cleanup, needs your decisions) → §3 (dashboard) → §4 (nav/Activity merge) last.

---

## Decisions I need from you
1. **worker/labor**: relabel both (keep both flows) **or** deprecate `labor`?
2. **supplier/vendor** and **payments-category**: confirm they're legacy so I can hide them?
3. **Dashboard**: implement the §3 layout as drawn, or want mock variants first?
4. **Scope**: stop at §1–§3 (this app, safe), or greenlight the §4 nav reconstruction too?
