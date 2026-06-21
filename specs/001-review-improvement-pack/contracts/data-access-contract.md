# Data Access Contract: Buildozer Review Improvement Pack

## General Rules

- Every workspace query is scoped by the active workspace.
- Financial reads and exports require owner, admin, or accounting-approved access before providers execute.
- Normal screens do not issue unbounded historical transaction reads.
- Existing offline queue overlays remain idempotent and are merged at most once.

## Notifications

**Read query**

- Collection: `notifications`
- Filters: `workspaceId == activeWorkspaceId`, `targetUserId == activeUserId`
- Order: `createdAt desc`
- Limit: 50

**Read-state update**

- Target user may update only `readAt` on a notification addressed to that user in the active workspace.
- Missing `readAt` is interpreted as unread.
- No new index is required for local unread counting from the bounded feed.

## Dashboard

- Use the existing maintained `workspace_metrics/{workspaceId}` document as the dashboard's single authoritative remote source.
- Backend recomputation extends that document from maintained `project_summaries`, current-week `weekly_summaries`, and project metrics; the client never scans those collections to compose the workspace dashboard.
- `recentTransactionRefs` is capped at 10 and all top-value ties resolve by amount descending, normalized name, then stable ID.
- Do not retain separate weekly-summary and weekly-insight streams that each query raw expenses and payments.
- Recent detail lookups are bounded by references/limits from workspace metrics.
- Merge pending local mutations using existing queue metadata, excluding synced actions already reflected remotely.
- Dashboard financial providers read `workspace_metrics` only for owner, admin, and accounting-approved roles. Denied roles render a localized restricted state and do not subscribe to the metrics document.

## Projects

- Warm active project stream: `isArchived == false`, ordered by most recent supported project timestamp, limit 50.
- Recent/name browse sorts query `projects` with a stable document-ID tie-breaker.
- Expense/income/net browse sorts query `project_metrics` with workspace, archive, and status filters; order by the selected metric descending, then `projectName`, then `projectId`.
- Financial sort cursors come from the metric query, project documents are hydrated by ID, and returned order is preserved across pages.
- Project browse page size: 20 with cursor continuation.
- Report selector: paged active and archived queries; archived inclusion is explicit.
- Search over already loaded pages is client-side unless a normalized indexed search field is already available.
- `project_metrics` reads, financial sort controls, and project-card financial fields are available only to owner, admin, and accounting-approved roles. Denied roles continue using status plus recent/name browsing without financial metric reads.

## Expenses and Payments

- Visible list page size remains 20.
- Bulk archive invokes the existing repository archive mutation once per selected ID; direct Firestore batch writes are forbidden.
- Partial archive failure must preserve failed IDs for retry.

## Reports

- Every report query includes `workspaceId`, selected `projectId`, inclusive `startDate`, and inclusive `endDate` where the repository supports them.
- Export page size remains 500, with cursor loops continuing until `hasMore == false` or no next cursor exists.
- Rows are defensively filtered again by project and date before aggregation/export.
- Main report charts/tables and export builders receive the same `ReportRequest` scope.
- No workspace-wide entity aggregation provider may supply a project-scoped custom export.

## Resource Directories

- Canonical collection: `entities`.
- Filters: `workspaceId` and exact entity `type`.
- Default page size: 20.
- Before rollout, run an idempotent cursor-batched admin migration for entities missing `lastUsedAt`, using `createdAt`, then `updatedAt`, then a fixed epoch fallback.
- Migration completion is a release prerequisite for enabling ordered directories; scanned/updated counts and the continuation cursor are recorded.
- Directory ordering: `lastUsedAt desc`, then normalized name, then entity ID.
- Accounting detail reads retain their existing role gate and bounded query limit/pagination.
- Domain accounting list and summary providers check accounting access before querying and render a friendly denied state when access is absent.

## Workers

- New records write `status` as `active`, `inactive`, or `terminated`.
- Old records missing `status` parse as `active`.
- `isArchived` remains required and independent from status.
- Worker mutation functions and Firestore validation accept only the three status values.
- Worker accounting records add optional `paidAmount`; new partial records require `0 < paidAmount < amount`.
- Paid records normalize to full amount and unpaid records to zero. Legacy partial records without a valid paid amount remain readable but are excluded from confirmed paid and confirmed remaining totals.
- `worker_accounting_summaries/{workerId}` stores exact totals across the full worker ledger and is the source of truth for worker summary cards.
- Domain accounting writes use typed repositories or mutation adapters with visible pending/failure handling; widgets do not call Firestore writes directly.

## Offline Queue

- Queue ordering remains monotonic even when timestamps collide.
- Individual retry changes only the selected failed/dead-letter item back to pending, clears retry scheduling/error fields as appropriate, and invokes the existing drain coordinator.
- Queue processing returns an outcome so applied and skipped-newer-version results can be serialized on recently synced actions.
- Existing serialized actions without outcome fields remain readable.

## Subscription Offers

- Price text comes only from RevenueCat store product metadata.
- Package/trial metadata may be absent and must be represented as nullable.
- Empty or failed offering loads produce UI error state; no monetary fallback is stored or displayed.

## Deployment Boundary

- Client-only slices require no Firebase deployment.
- Notification `readAt` rules, maintained metric rules, domain-accounting rules, worker status or worker-summary recomputation, and admin backfill commands require functions/rules tests and targeted deployment planning.
- Firestore indexes are changed only when an implemented query fails with a verified missing-index requirement.
