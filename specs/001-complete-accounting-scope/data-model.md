# Data Model: Complete Accounting Scope

## Attachment

Represents a supporting document or media file for a transaction or accounting entity.

**Fields**

- `id`: stable attachment identifier.
- `fileName`: user-facing file name.
- `contentType`: MIME type or known file type.
- `size`: file size in bytes.
- `attachmentType`: invoice, receipt, image, pdf, or document.
- `storagePath`: remote file storage path once uploaded.
- `downloadUrl`: optional remote access URL when available.
- `localPath`: local pending file path while offline or before upload.
- `uploadStatus`: pending, uploading, uploaded, failed, missingLocalFile.
- `uploadedAt`: date/time when upload completed.
- `uploadedBy`: user who uploaded or queued the attachment.
- `errorMessage`: recoverable failure message when upload/open fails.

**Relationships**

- Belongs to one expense, payment, entity, worker, contractor, transport provider, equipment provider, or accounting record.

**Validation Rules**

- Must have a file name, supported type, non-zero size, and size under the configured limit.
- Firestore records store metadata only; binary/base64 file content is not stored in Firestore.
- Offline attachments must retain enough local reference data to retry upload after reconnecting.

**State Transitions**

`pending -> uploading -> uploaded`

`pending -> failed -> pending`

`pending -> missingLocalFile`

## Expense

Represents a project or workspace cost.

**Fields**

- `id`, `workspaceId`, `projectId`, `projectName`
- `category`: materials, labor, transport, equipment, storage, rentals, payments, other.
- `entityId`, `entityName`, `entityType`
- `supplierName`, `workerName`, `contractorName`
- `purpose`
- `description`
- `amount`, `currency`
- `date`
- `paymentMethod`
- `paymentStatus`: unpaid, partial, paid, refunded, cancelled, or project-supported equivalent.
- `notes`
- `attachments`
- `createdAt`, `createdBy`, `updatedAt`, `updatedBy`
- `syncStatus`: synced, pendingCreate, pendingUpdate, failed.

**Relationships**

- Belongs to a workspace and optionally a project.
- References one primary entity where available.
- Has zero or more attachments.
- Contributes to category, weekly, project, workspace, and entity summaries.

**Validation Rules**

- Amount must be positive.
- Date, category, payment method, payment status, and project/workspace scope are required.
- Old records without newer fields must load with fallback values.
- Typed entity data must be retained even if entity suggestion sync fails.

**State Transitions**

`draft -> pendingCreate -> synced`

`synced -> pendingUpdate -> synced`

`pendingCreate|pendingUpdate -> failed -> pendingCreate|pendingUpdate`

## Payment

Represents payment or income activity.

**Fields**

- `id`, `workspaceId`, `projectId`, `projectName`
- `entityId`, `entityName`, `entityType`
- `amount`, `currency`
- `date`
- `paymentMethod`
- `paymentStatus`
- `description`
- `notes`
- `attachments`
- `createdAt`, `createdBy`, `updatedAt`, `updatedBy`
- `syncStatus`

**Relationships**

- Belongs to a workspace and optionally a project.
- References one primary entity where available.
- Has zero or more attachments.
- Contributes to weekly, project, workspace, payment, and entity summaries.

**Validation Rules**

- Amount must be positive.
- Date, method, status, and project/workspace scope are required.
- Old records without entity metadata must use name fallback matching where possible.

## Entity

Represents a reusable accounting party.

**Fields**

- `id`, `workspaceId`
- `type`: supplier, vendor, worker, contractor, transportProvider, equipmentProvider, other.
- `name`
- `normalizedName`
- `aliases`
- `contactInfo`
- `notes`
- `attachments`
- `lastUsedAt`
- `createdAt`, `createdBy`, `updatedAt`, `updatedBy`

**Relationships**

- Referenced by expenses and payments.
- Has one entity summary.
- May have attachment metadata and transaction history.

**Validation Rules**

- Name is required.
- `normalizedName` must be unique per workspace and type.
- Suggestions should return recent matching entities first.

## Entity Summary

Maintained summary for normal entity aggregation screens.

**Fields**

- `workspaceId`, optional `projectId`
- `entityId`, `entityName`, `entityType`
- `totalExpenses`
- `totalPayments`
- `totalPaid`
- `remainingBalance`
- `transactionCount`
- `attachmentCount`
- `latestTransactionDate`
- `categoryBreakdown`
- `paymentMethodBreakdown`
- `updatedAt`

**Relationships**

- Derived from expenses, payments, and attachments.
- Links to transaction history queries scoped by entity and date.

**Validation Rules**

- Must not double count pending offline actions once synced.
- Must be recomputable from bounded transaction sets for verification.

## Category Summary

Represents totals for an expense category.

**Fields**

- `workspaceId`, optional `projectId`
- `category`
- `totalAmount`
- `transactionCount`
- `latestTransactionDate`
- `updatedAt`

**Relationships**

- Derived from expenses.
- Used by category groups, dashboards, and reports.

## Weekly Summary

Maintained current-week operating summary.

**Fields**

- `workspaceId`, optional `projectId`
- `weekStart`, `weekEnd`
- `totalExpenses`
- `totalPayments`
- `topEntity`
- `topCategory`
- `laborSummary`
- `equipmentSummary`
- `paymentSummary`
- `recentTransactionRefs`
- `updatedAt`

**Validation Rules**

- Week range must include both lower and upper date bounds.
- Future-dated transactions outside the week must be excluded.
- Pending offline deltas must be included once and removed or reflected after sync.

## Report Request

Represents a user-requested export.

**Fields**

- `reportType`: expenses, payments, entities, workers, contractors, daily, weekly, filtered, combined.
- `workspaceId`, optional `projectId`
- `dateRange`
- `filters`
- `selectedSections`
- `requestedBy`
- `generatedAt`

**Validation Rules**

- Financial report/export access requires owner, admin, or accounting-approved role.
- Reports must include title, scope name, generated date, applied filters, totals, sections, and attachment indicators.
- Date-scoped reports may recalculate exact totals over the selected range.

## Offline Action

Represents a queued create/update mutation.

**Fields**

- `id`
- `workspaceId`, optional `projectId`
- `type`: expenseCreate, expenseUpdate, paymentCreate, paymentUpdate, attachmentUpload, entityUpsert, summaryDelta.
- `payload`
- `localAttachmentRefs`
- `status`: pending, syncing, synced, failed, deadLetter.
- `attemptCount`
- `lastError`
- `createdAt`, `updatedAt`
- `clientSavedAt`

**Validation Rules**

- Last saved change wins for conflicts.
- Pending actions must merge into supported lists/summaries exactly once.
- Failed actions must remain recoverable and visible.

## Access Role

Represents workspace accounting permissions.

**Fields**

- `workspaceId`
- `userId`
- `role`: owner, admin, accountingApproved, member, entryOnly.
- `grantedAt`, `grantedBy`

**Validation Rules**

- Reports, exports, balances, and attachments require owner/admin/accountingApproved.
- Entry workflows may remain available to non-accounting-approved roles when workspace rules allow it.
