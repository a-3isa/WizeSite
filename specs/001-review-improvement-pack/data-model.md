# Data Model: Buildozer Review Improvement Pack

This feature primarily adds presentation and query state around existing accounting records. Persistent changes remain backward-compatible and are limited to notification read state, worker status, optional worker `paidAmount`, added fields on the existing maintained workspace metrics document, maintained `worker_accounting_summaries`, subscription offer metadata exposed by the purchase adapter, local sync resolution metadata, and backfilled entity ordering or worker-summary initialization data.

## Primary Navigation Destination

Represents one stable branch in the signed-in shell.

**Fields**

- `branchIndex`: stable indexed-shell position.
- `route`: canonical destination route.
- `labelKey`: localized label key.
- `icon`: unselected icon.
- `selectedIcon`: selected icon.
- `semanticLabelKey`: assistive-technology label.
- `badgeCount`: optional bounded count, used by notification entry points.

**Validation Rules**

- Home and Projects must each map to exactly one reachable branch; the center Add control opens the add-action popup and Reports remain reachable from project-scoped report actions rather than as a standalone shell branch.
- Branch indexes must not change based on locale or workspace state.
- Re-selecting the active branch returns it to its initial location using existing shell behavior.

## Notification Item

Represents a targeted user notification.

**Existing Fields**

- `workspaceId`
- `targetUserId`
- `title`
- `message`
- `createdAt`

**New Field**

- `readAt`: nullable timestamp; missing or null means unread.

**Validation Rules**

- Only the targeted user may read the notification.
- A targeted user update may change only `readAt`; all targeting and message fields remain immutable.
- The shell badge is derived from the bounded targeted feed and never displays a negative count.

**State Transitions**

`unread -> read`

Read state is monotonic in this feature; marking an item unread again is out of scope.

## Dashboard Snapshot

An in-memory presentation model that keeps dashboard sections coherent.

**Fields**

- `activeProjectCount`
- `totalExpenses`
- `totalIncome`
- `net`
- `weeklyExpenses`
- `weeklyIncome`
- `weeklyNet`
- `topEntity`
- `topCategory`
- `laborTotal`
- `equipmentTotal`
- `paymentSummary`
- `recentTransactions`
- `pendingSyncCount`
- `failedSyncCount`
- `generatedFrom`: summary identifiers and local queue revision used for diagnostics.

**Relationships**

- Derived from one maintained `workspace_metrics/{workspaceId}` snapshot and the local offline queue.
- Does not create a new Firestore document.

## Workspace Dashboard Metrics

Extends the existing maintained workspace metrics document so normal dashboard loads remain one bounded remote read.

**Added Fields**

- `weekStart`
- `weeklyExpenses`
- `weeklyIncome`
- `weeklyNet`
- `topEntity`
- `topCategory`
- `laborSummary`
- `equipmentSummary`
- `paymentSummary`
- `recentTransactionRefs`: bounded to the 10 most recent references.
- `updatedAt`

**Validation Rules**

- Backend recomputation aggregates only maintained project/weekly summary data and writes one workspace document.
- Top values use deterministic amount-descending then normalized-name/ID tie-breakers.
- Missing top values remain empty and are rendered with explanatory fallback copy.
- The client does not query all project or weekly summary documents to compose the dashboard.
- Accounting-authorized roles may load the maintained workspace metrics document. Denied roles receive a localized restricted-financial state and do not subscribe to the maintained metric document.

**Validation Rules**

- Pending local mutations are represented at most once.
- Missing top values become a localized no-data state, not the literal `unassigned` label.
- A refresh invalidates all snapshot sources as one user action.

## Voice Capture Session

Temporary state for one voice expense recording.

**Fields**

- `state`: idle, recording, ready, playing, processing, failed.
- `elapsedSeconds`
- `maximumSeconds`: 60.
- `remainingSeconds`
- `recordingPath`
- `audioLevelSamples`
- `errorKey`
- `currency`

**Validation Rules**

- Recording stops automatically at 60 seconds.
- Playback is available whenever a valid ready recording exists.
- Currency defaults to current user settings and falls back to EGP only when settings are unavailable.
- Raw exception strings are not displayed.

**State Transitions**

`idle -> recording -> ready -> processing`

`ready -> playing -> ready`

`recording|ready|playing -> idle` on cancel or rerecord

`recording|playing|processing -> failed -> idle|ready` depending on recoverability

## Transaction Filter Set

Represents active expense or payment filtering and grouping.

**Fields**

- `searchText`
- `projectId`
- `entityId`
- `entityType`
- `category` where applicable
- `paymentMethod`
- `paymentStatus`
- `startDate`
- `endDate`
- `groupBy`

**Validation Rules**

- Each visible filter token maps to exactly one field and clears only that field.
- `groupBy` is presentation state and is not represented as a narrowing filter token.
- Date range requires `startDate <= endDate`.

## Transaction Selection

Temporary multi-select state for expenses or payments.

**Fields**

- `recordType`: expense or payment.
- `selectedIds`: unique record identifiers.
- `action`: archive for the first implementation.
- `inProgressIds`
- `failedIds`

**Validation Rules**

- Selection is cleared when list scope changes.
- Archive requires confirmation and calls the existing repository mutation for each selected record.
- A partial failure keeps failed records selected and reports a recoverable result.

## Project Browse Query

Represents a bounded project list or selector request.

**Fields**

- `workspaceId`
- `status`: all, active, completed, onHold.
- `includeArchived`
- `sort`: recent, name, highestExpense, highestIncome, highestNet.
- `searchText`
- `pageSize`: 20 for full browse/select screens.
- `cursor`

**Validation Rules**

- The warm active-project stream is capped at 50.
- Full project and report selectors use cursor paging.
- Archived projects appear in report selection only when explicitly included.
- `recent` and `name` sorts page through project fields using a stable document-ID tie-breaker.
- `highestExpense`, `highestIncome`, and `highestNet` page through maintained `project_metrics`, filtered by workspace/archive/status and ordered by the selected metric descending, then `projectName`, then `projectId`.
- Financially sorted pages hydrate project documents by returned IDs and preserve metric-query order; they are never re-sorted independently per loaded page.
- Only accounting-authorized roles can request financial sorts or financial project-card metrics. Denied roles retain status filtering and recent/name ordering without project financial cards.

## Report Request

Existing domain model used as the canonical report scope.

**Fields**

- `projectId`
- `sections`
- `startDate`
- `endDate`

**Validation Rules**

- Project ID is required before financial providers load.
- The default date range is month-to-date when no explicit dates are selected.
- Main charts, recent tables, custom export data, and single-chart export use the same project/date scope.
- Paged export collection continues until exhaustion and filters every row by project and inclusive date range.

## Managed Resource Directory Entry

Represents a contractor, equipment provider, or transport provider in a cross-project directory.

**Fields**

- `entityId`
- `workspaceId`
- `type`: contractor, equipmentProvider, transportProvider.
- `name`
- `normalizedName`
- `lastUsedAt`
- `attachmentCount`
- `summary`: optional accounting totals available to approved roles.

**Relationships**

- Backed by the existing `entities` collection.
- Opens the existing typed accounting route for the selected entity.

**Validation Rules**

- Lists are type-filtered and paginated.
- Financial totals are not loaded or displayed for denied accounting roles.
- Before ordered paging is enabled, an idempotent cursor-batched admin migration assigns missing `lastUsedAt` from `createdAt`, then `updatedAt`, then a fixed epoch fallback.
- Migration progress records scanned and updated counts and supports safe continuation after interruption.
- New and updated entity records always write `lastUsedAt`; directory ordering is `lastUsedAt` descending, then normalized name, then entity ID.

## Worker Accounting Record

Extends the existing worker accounting record without changing historical amounts.

**Added Field**

- `paidAmount`: nullable numeric amount explicitly paid toward a partial record.

**Derived Summary Fields**

- `totalCost`: sum of every record amount.
- `confirmedPaid`: paid records contribute full amount, unpaid records contribute zero, and partial records contribute their valid explicit `paidAmount`.
- `confirmedRemaining`: sum of `amount - confirmedPaid` only for records whose paid amount is determinable.
- `unresolvedPartialCount`: number of legacy partial records without a valid explicit `paidAmount`.

**Validation Rules**

- New partial records require `paidAmount > 0` and `paidAmount < amount`.
- Paid records normalize to `paidAmount == amount`; unpaid records normalize to `paidAmount == 0`.
- Legacy partial records without `paidAmount` remain readable but do not contribute to confirmed paid or remaining totals.
- Any unresolved partial records produce an incomplete-data explanation alongside the summary.
- Worker-only partial-payment controls are isolated to worker accounting flows; contractor, equipment, and transport accounting records continue using the generic payment-status model without `paidAmount`.

## Worker Accounting Summary

Maintains exact worker totals across the full ledger, independent of the visible page size.

**Fields**

- `workspaceId`
- `workerId`
- `totalCost`
- `confirmedPaid`
- `confirmedRemaining`
- `unresolvedPartialCount`
- `recordCount`
- `updatedAt`

**Validation Rules**

- The summary maintains exact worker totals across the full set of worker accounting records for that worker.
- Screen-level totals never sum only the visible list page.
- `unresolvedPartialCount` increments for legacy partial records without a valid explicit `paidAmount`.
- Reads are restricted to accounting-authorized roles.

## Worker Profile

Extends the existing worker record.

**New Field**

- `status`: active, inactive, terminated; missing values default to active.

**Existing Lifecycle Field**

- `isArchived`: controls whether the worker appears in normal active queries.

**Validation Rules**

- Status is required on new writes and validated by client, function, and Firestore rules.
- Editing status does not implicitly archive the worker.
- Archiving remains a separately confirmed action.

## Subscription Offer View

Extends the existing `OfferingPackage` adapter model.

**Fields**

- `id`
- `title`
- `priceString`: store-provided localized price only.
- `periodLabel`
- `productCode`
- `offeringId`
- `packageType`
- `trialPeriodLabel`: nullable store-provided introductory/trial period.
- `isRecommended`: derived from product policy, normally annual when available.
- `featureKeys`: local product-capability comparison keys.

**Validation Rules**

- No fallback monetary value is fabricated.
- Empty offers produce a retryable unavailable state.
- Trial copy is shown only when metadata supports it.

## Offline Action Resolution

Extends the existing local `OfflineAction` serialization.

**New Fields**

- `resolutionType`: nullable; `applied` or `skippedNewerVersion`.
- `resolutionAt`: nullable timestamp.
- `resolutionTargetId`: nullable affected record identifier.

**Validation Rules**

- Existing serialized actions without resolution fields continue to parse.
- A stale last-saved update is stored as synced with `skippedNewerVersion`, not failed.
- Resolution metadata remains visible during the existing recently-synced retention window.

**State Transitions**

`pending|failed -> synced(applied)`

`pending|failed -> synced(skippedNewerVersion)`

`pending|failed -> deadLetter`
