# Research: Buildozer Review Improvement Pack

## Decision: Deliver the review as gap-first user-story slices

**Rationale**: The branch already contains completed accounting/report fixes and passes the current analyzer and Flutter test suite. Starting each slice with a focused gap test prevents duplicate work and protects the existing behavior.

**Alternatives considered**:

- Rewrite each reviewed screen from the wireframes: rejected because it would discard working accounting and offline behavior.
- Treat the review as one large UI refactor: rejected because failures would be difficult to isolate and the constitution requires incremental delivery.

## Decision: Use a four-branch indexed shell and make AddHub canonical

**Rationale**: The router already has an indexed shell with an unreachable `AddHubScreen`. Home, Add, Reports, and Projects can become stable branches while the add hub preserves all current creation actions. Retiring the arc launcher removes duplicate navigation state and its fixed-angle RTL risk.

**Alternatives considered**:

- Keep the two-tab shell and add more dashboard links: rejected because core destinations would remain hidden.
- Keep both the arc launcher and a full Add destination: rejected because two competing add experiences create inconsistent semantics and repeated-tap behavior.

## Decision: Store notification read state as nullable `readAt`

**Rationale**: The existing feed is already bounded to 50 targeted notifications. Missing or null `readAt` can safely mean unread for old records, while a strict Firestore update rule can let the target user change only `readAt`.

**Alternatives considered**:

- Badge every notification: rejected because the result would not represent unread state.
- Store last-viewed time only on the device: rejected because unread state would diverge across devices.
- Add a callable function only for marking read: rejected because a narrowly constrained Firestore update is simpler and testable in rules.

## Decision: Compose dashboard state from maintained workspace metrics and the offline queue

**Rationale**: The existing `workspace_metrics/{workspaceId}` document is already maintained by backend recomputation. Extend that document with current-week totals, top entity/category, labor/equipment/payment summaries, and bounded recent transaction references aggregated from project-scoped maintained summaries. A single `DashboardSnapshot` provider can then read one authoritative remote document, merge pending local deltas, and eliminate duplicate live expense/payment queries without scanning every project summary on a normal dashboard load.

**Alternatives considered**:

- Continue querying expenses and payments twice: rejected for duplicate reads and fragmented loading states.
- Query every project or weekly summary from the dashboard client: rejected because workspace growth would turn the home screen into an unbounded read.
- Introduce a new dashboard collection: rejected because extending the existing maintained `workspace_metrics` document provides the bounded read contract without another data surface.

## Decision: Gate dashboard and project financial metrics by accounting role

**Rationale**: `workspace_metrics` and `project_metrics` contain restricted financial data. Owners, admins, and accounting-approved users can see those values, but members and entry-only users still need the shell, quick actions, project browsing, and non-financial sorting. The client should short-circuit metric providers for denied roles and render a localized restricted state instead of allowing broad metric reads or silently hiding broken cards.

**Alternatives considered**:

- Let every workspace member read maintained metrics: rejected because the constitution requires financial summaries and balances to stay restricted.
- Block denied users from the full dashboard or projects screen: rejected because the review only requires financial restriction, not removal of general navigation and operational browsing.

## Decision: Replace blank states with shared presentation primitives

**Rationale**: Dashboard, reports, notifications, workers, settings, and domain accounting screens repeat loading/error/empty patterns. Small shared widgets for skeletons, recoverable errors, and empty CTAs improve consistency without creating a new design system.

**Alternatives considered**:

- Fix each screen independently: rejected because raw errors and blank loading states would drift again.
- Build a broad component library first: rejected as unnecessary for this feature.

## Decision: Model voice recording as a bounded state machine

**Rationale**: Explicit idle, recording, ready, playing, processing, and failed states make the 60-second timer, playback, cancellation, and visual feedback testable. The existing recorder and audio player remain in use.

**Alternatives considered**:

- Extend only the integer timeout: rejected because it would not solve missing progress, waveform, playback, or raw errors.
- Add server-side recording state: rejected because capture state is local and temporary.

## Decision: Limit the first bulk transaction action to archive

**Rationale**: Expense and payment repositories already expose offline-safe archive mutations with quota handling. Multi-select archive can reuse those paths and preserve idempotency. Permanent bulk delete is not currently a supported repository operation.

**Alternatives considered**:

- Add permanent bulk deletion: rejected because it expands backend and recovery risk beyond the reviewed UI need.
- Perform direct Firestore batch writes: rejected because it would bypass the mutation service and offline queue.

## Decision: Cap warm project streams and paginate every full browse/select flow

**Rationale**: The active `projectsProvider` is an unbounded real-time stream, while repository page APIs already exist. A capped recent-active stream remains useful for prefill and quick actions; project screens and report selectors use cursor paging and explicit archived inclusion.

**Alternatives considered**:

- Remove all project streams: rejected because quick-entry prefill benefits from a small warm set.
- Load every active and archived project into selectors: rejected for large-workspace cost and latency.

## Decision: Execute financial project sorts from project metrics

**Rationale**: Expense, income, and net values live in maintained `project_metrics` documents. Financial sorts therefore query that collection directly using workspace, archive, and status filters, order by the selected metric plus a stable project-name/project-ID tie-breaker, and hydrate project records in returned metric order. Sorting a `createdAt` page after metrics are fetched would only sort inside that page and produce incorrect global ordering.

**Alternatives considered**:

- Sort each loaded project page in memory: rejected because records on later pages could belong before records already displayed.
- Copy every financial metric onto project documents: rejected because `project_metrics` is already the maintained authoritative source and duplicating values adds drift risk.

## Decision: Use one report scope for charts, tables, and exports

**Rationale**: Project and date must not drift between report sections. The existing `ReportRequest` and paged `ReportExportDataBuilder` provide the correct base; a report-scope provider will drive all visual and export providers.

**Alternatives considered**:

- Keep date state only inside the custom-export sheet: rejected because main charts would remain all-time.
- Recompute reports from workspace-wide aggregation documents: rejected because exact project/date scoping is required.

## Decision: Share single charts as focused PDFs

**Rationale**: The project already uses `pdf` and `printing`. Generating a one-chart PDF from chart data avoids screenshot fragility and provides a consistent share/save path without another sharing dependency.

**Alternatives considered**:

- Capture widget screenshots: rejected because pixel ratio, lifecycle, and off-screen rendering make tests brittle.
- Add a new image-sharing package: rejected because existing printing support is sufficient.

## Decision: Build resource directories from the canonical entities collection

**Rationale**: Contractors, equipment providers, and transport providers already appear as typed entities and have accounting detail routes. Paged type-filtered directories avoid inventing duplicate collections and allow cross-project browsing. The top-level Add destination will expose a visible Resources section linking to workers and all three typed directories so route existence is not mistaken for discoverability.

**Alternatives considered**:

- Aggregate names from accounting records on every screen load: rejected for duplicate records and unbounded reads.
- Create three new master collections: rejected because the `entities` collection is already the canonical reusable party model.

## Decision: Backfill legacy entity ordering before enabling paged directories

**Rationale**: Firestore ordering excludes documents that do not contain the ordered field. Before the new directories depend on `lastUsedAt`, an idempotent cursor-batched admin migration will assign missing values from `createdAt`, then `updatedAt`, then a fixed epoch fallback. New and updated entity writes continue setting `lastUsedAt`. The migration records scanned/updated counts and can be safely resumed.

**Alternatives considered**:

- Merge an ordered query with an unbounded client scan for missing fields: rejected because it breaks predictable pagination and scalable data access.
- Ignore legacy documents: rejected because valid resources would disappear from the new directories.

## Decision: Add a backward-compatible worker status field

**Rationale**: `status` values `active`, `inactive`, and `terminated` satisfy the review while `isArchived` continues to control whether a record is hidden. Old workers default to `active`. The existing mutation function and Firestore validation must accept the new field.

**Alternatives considered**:

- Derive status entirely from `isArchived`: rejected because inactive and terminated are distinct business states.
- Replace `isArchived` with status: rejected because it would break existing queries and lifecycle behavior.

## Decision: Require explicit paid amounts for partial worker records

**Rationale**: Worker accounting records contain a total amount and payment status, but a partial status alone cannot determine how much was paid. Add an optional `paidAmount`: paid records resolve to the full amount, unpaid records resolve to zero, and new partial records require a value greater than zero and less than the total amount. Legacy partial records without `paidAmount` remain visible but are excluded from confirmed paid/remaining totals and produce an incomplete-data explanation.

**Alternatives considered**:

- Treat half of every partial record as paid: rejected because it fabricates accounting values.
- Treat the full partial record as paid or unpaid: rejected because either interpretation can materially misstate balances.

## Decision: Maintain exact worker accounting summaries separately from paged ledger rows

**Rationale**: The worker accounting screen shows a paged ledger for readability, but FR-024 requires exact totals across the full worker history. A maintained `worker_accounting_summaries` document per worker can store total cost, confirmed paid, confirmed remaining, unresolved partial count, and record count without forcing an unbounded client aggregation on a normal screen load.

**Alternatives considered**:

- Sum only the first visible page of records: rejected because it silently understates balances.
- Page through every worker record on every screen load: rejected because it breaks scalable normal-screen reads.

## Decision: Keep worker partial-payment controls isolated and move domain accounting writes behind typed repositories

**Rationale**: `paidAmount` is meaningful only for worker accounting. Contractor, equipment, and transport screens should retain the generic accounting-entry experience without worker-only partial-payment controls. The shared ledger UI should delegate saves through typed repositories or mutation adapters with visible pending and recoverable failure states rather than writing directly from the widget.

**Alternatives considered**:

- Add `paidAmount` to every domain accounting flow: rejected because it introduces a worker-specific concept where it does not belong.
- Keep direct `doc.set()` writes inside the shared screen: rejected because it hides failures, bypasses typed validation boundaries, and makes role enforcement harder to reason about.

## Decision: Show only live RevenueCat offers and extend offer metadata

**Rationale**: Store-provided price strings are localized and trustworthy. `OfferingPackage` will expose package type and available introductory/trial metadata; local comparison content explains product features without fabricating prices.

**Alternatives considered**:

- Keep hardcoded price fallbacks: rejected because they are wrong outside USD regions.
- Hide the plans screen when RevenueCat is unavailable: rejected because a retryable unavailable state is more useful.

## Decision: Use local PNG branding and existing Firebase session restoration

**Rationale**: The app already has branding PNGs and does not need an SVG dependency. The login screen can reserve a stable Google-button slot while support is checked. Firebase Auth/session restore already provides the normal returning-user path, so no biometric or custom credential storage is added.

**Alternatives considered**:

- Continue loading the Google logo from the network: rejected because sign-in branding should not depend on third-party availability.
- Add biometric sign-in in this pack: rejected because it introduces platform credential policy and storage scope not required by the review.

## Decision: Persist sync resolution outcomes in the local queue

**Rationale**: Last-saved-change-wins already skips stale queued updates, but users cannot see that decision. Returning an `OfflineActionOutcome` from queue processing and storing resolution metadata on the synced action makes the outcome visible during the existing synced-item retention window.

**Alternatives considered**:

- Show only a transient snackbar: rejected because the user may not be watching during background sync.
- Add a server conflict log: rejected because the conflict decision currently occurs in the local queue.

## Decision: Keep backend changes narrowly scoped

**Rationale**: Most recommendations remain client presentation and bounded-query changes. Backend work is limited to notification read-state enforcement, accounting-only access rules for maintained metrics and domain accounting collections, worker status and partial-payment validation, extending the existing workspace metrics recomputation, maintaining exact worker accounting summaries, and idempotent backfills for entity ordering or worker-summary initialization. Existing report summary functions are reused, and query indexes are added only for verified implemented paths.

**Alternatives considered**:

- Deploy functions/rules for every slice: rejected because most slices do not alter backend contracts.
- Declare the entire pack client-only: rejected because unread state, restricted metric access, worker validation, exact worker summaries, bounded workspace dashboard composition, and legacy entity visibility require maintained or privileged backend work.
