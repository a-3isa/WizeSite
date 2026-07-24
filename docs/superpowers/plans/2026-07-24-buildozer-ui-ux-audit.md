# Buildozer UI/UX Audit Implementation Plan

Source: `BUILDOZER_UI_UX_AUDIT.md` (964-line audit). User approved FULL scope
("everything incl. red-tier features"), 2026-07-24.

Branch: `002-buildozer-v2-design-system`. Executed via subagent-driven
development (implementer + task-reviewer per task, fixes, ledger in
`.superpowers/sdd/progress.md`).

Global constraints (unchanged from the v2 design system already on this branch):
accent `#FF6D00`/dark `#FF7D1F`; income green `#12A150`, expense red `#E5484D`,
warning amber `#F59E0B`; outlined icons only, no gradients/photography/emoji;
Title Case titles / sentence-case body; radii 10/14/20/26/pill; primary CTA 56px;
bilingual EN/AR RTL; token-driven via `context.tokens`; `flutter analyze` clean +
`flutter test` green gate. Presentation reuses DS primitives in
`lib/core/widgets/ds/`.

Audit items already satisfied by Tasks 1-15 (SKIP): typography case, empty states
(`AppEmptyState`), color semantics, card consistency, activity grouping+filters+
search, loading skeletons, error/retry, money-row dates.

---

## PHASE A — Green-tier UI wins (no new data model)

### A1: Project selector → bottom sheet + search
Replace `_DashboardProjectSelector` `PopupMenuButton` (dashboard_screen.dart) with
a bottom sheet mirroring `workspace_switcher_sheet.dart`: "All Projects" + project
list, search field when >~6 projects, token-styled, full-width trigger. (Prob 12-14)

### A2: FAB size reduction
Shrink the raised center FAB in `build_bottom_nav.dart` ~12% while keeping
prominence; verify nav balance + tap target ≥48dp. (Prob 9, 29)

### A3: Budget-Used card — remaining + color transitions
In project financial hero / dashboard budget card: show "X remaining" alongside
%, and transition bar color green→amber→red as usage rises. (Prob 4-home)

### A4: KPI reordering + Contract Value demotion
Reorder project-scoped overview so Net Profit / Remaining Budget lead; Contract
Value becomes a smaller secondary stat. (Prob 2, 3-home)

### A5: Trend indicators
Add ▲/▼ % vs last week to income/expense/net where `dashboardWeeklySummaryProvider`
already provides the data. Color + arrow (not color alone). (Prob 7)

### A6: Resource rows — counts + Workers emphasis
Show live entity counts (Workers (N), Equipment (N)…) and give Workers visual
priority in `_ResourceLinks`. (Prob 20, 21)

### A7: "Weekly Summary" → explicit "Last 7 days"
Relabel + add "vs last 7 days" comparison sub-line. (Prob 18, 19)

---

## PHASE B — Red-tier DERIVABLE from existing data (light aggregation + UI)

### B1: Project progress + timeline
Surface existing `completionPercentage` as a progress ring/bar, and derive
"Timeline: N days remaining / M% elapsed" from `startDate`+`expectedEndDate` on
Project. Dashboard + project detail. (Prob 6, construction §)

### B2: Worker attendance summary
Aggregate worker entries into "Today's workers / this week man-days" card from the
existing worker-entry data. (construction §, Prob-home 6)

### B3: Outstanding payments / cash collected
Derive from payments `paymentStatus` (paid vs unpaid) + expenses: Cash Collected,
Outstanding (unpaid) — surface on dashboard. (construction §)

### B4: Profit margin + remaining budget KPIs
Compute margin = net/income, remaining = budgetLimit−expenses; add as first-class
dashboard KPIs. (construction §)

### B5: Warnings/alerts strip
Derive from existing data: budget exceeded (expenses>budgetLimit), over-contract,
unpaid-payment count. Dashboard alert chips. (Prob 16)

---

## PHASE C — Net-new subsystems (each needs schema + CF + a product decision)

C1 Invoices · C2 RFIs/open issues · C3 Milestones · C4 Pending approvals surfacing ·
C5 Weather (optional) · C6 Safety alerts (optional) · C7 AI/predictive insights.

Each: brainstorm the model + surface the 1-2 product decisions BEFORE building
(field shapes, entry method, who can approve). Do NOT invent schemas silently.
Build after Phases A+B land and are reviewed.

---

## PHASE D — P2 polish (cross-cutting, after features exist)

Animations (number counting, progress, pull-to-refresh already partly present),
48dp touch-target audit, screen-reader label pass, transitions. (Prob 30, P2, a11y)

## Data bug (Prob 1, 31)
Likely already fixed by this session's seed rewrite (writes `project_metrics`).
Confirm via manual reseed+login (outstanding manual-QA step). If the per-project
scoped view still reads 0, fix the project-doc/`project_metrics` merge path.
