# Feature Specification: Complete Accounting Scope

**Feature Branch**: `001-complete-accounting-scope`

**Created**: 2026-05-27

**Status**: Draft

**Input**: User description: "Complete and fix every missing original product-scope item in the existing project management and accounting application, preserving working features and closing the verified gaps in attachments, exports, expense entry, entities, aggregation, dashboard, quick entry, grouping, filters, summaries, offline behavior, scalability, error handling, and tests."

## Clarifications

### Session 2026-05-27

- Q: Should the completion scope include listed domains even if the existing app does not yet have base contractor, equipment, worker accounting, or related accounting sections? -> A: Build all listed domains even if the app has no existing contractor/equipment/worker accounting section yet.
- Q: How should transactions with attachments behave while offline? -> A: Save the transaction and all attachment references offline, show pending attachment state, then upload and sync everything automatically after reconnecting.
- Q: Who can view or export financial reports, balances, and attachments? -> A: Only workspace owners, admins, and accounting-approved roles can view or export financial reports, entity balances, and attachments.
- Q: How should conflicts be resolved when the same transaction changes offline and remotely? -> A: Last saved change wins automatically.
- Q: How should normal dashboards and aggregation avoid unbounded historical reads while keeping report totals accurate? -> A: Use maintained summary records for normal screens, with bounded exact recalculation for date-scoped reports.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capture Complete Accounting Transactions (Priority: P1)

Project staff record expenses and payments with the structured information needed for accurate accounting, including category, related person or company, purpose, amount, date, payment method, payment status, notes, project or workspace scope, and supporting documents.

**Why this priority**: Accurate transaction capture is the foundation for every report, dashboard, filter, aggregation, and offline workflow.

**Independent Test**: A user can create, edit, view, and filter an expense and a payment with all required accounting fields and attachments while existing records without newer fields continue to load.

**Acceptance Scenarios**:

1. **Given** a user is entering an expense, **When** they provide category, entity, purpose, amount, date, payment method, payment status, notes, and attachments, **Then** the transaction is saved with all visible fields and appears in the expense list.
2. **Given** an old expense or payment record lacks newer entity or attachment fields, **When** the user opens or lists it, **Then** the record loads without crashing and displays sensible fallback values.
3. **Given** a file is invalid, oversized, missing, or fails to upload, **When** the user attempts to attach it, **Then** the user sees a clear recoverable error and no corrupt transaction is created.
4. **Given** the user is offline and adds valid attachments to a transaction, **When** they save, **Then** the transaction and attachment references are saved locally with a pending state and sync automatically after reconnecting.

---

### User Story 2 - Find, Group, and Summarize Accounting Activity (Priority: P1)

Project owners and accountants quickly understand spending and payments by filtering, searching, grouping, and reviewing summary cards across expenses, payments, categories, entities, and time ranges.

**Why this priority**: Users need fast answers during daily project operations without exporting data or manually calculating totals.

**Independent Test**: A user can combine filters, search text, and group modes; totals and counts remain correct and include pending offline items where supported.

**Acceptance Scenarios**:

1. **Given** expenses exist across categories, entities, dates, payment methods, and payment statuses, **When** the user applies combined filters, **Then** only matching records appear and active filters can be cleared.
2. **Given** matching expenses are displayed, **When** the user groups by date, relative date, category, entity, or payment method, **Then** each group shows the correct title, total, count, and collapsible body.
3. **Given** the expenses page opens, **When** data loads, **Then** today, current week, current month, and transaction count summaries are visible for the active project or workspace.

---

### User Story 3 - Reuse Entities and See Entity-Level Accountability (Priority: P2)

Users reuse suppliers, workers, contractors, transport providers, equipment providers, and other entities through suggestions, then review balances, totals, transaction history, attachments, and breakdowns by entity.

**Why this priority**: Reusable entities prevent duplicate names and enable reliable balances and history across projects.

**Independent Test**: A user can create or reuse an entity from transaction entry, see recent suggestions first, prevent duplicates by normalized name, and open an aggregation view with correct totals and history.

**Acceptance Scenarios**:

1. **Given** an entity was used before, **When** the user types a similar name in an entry form, **Then** matching suggestions appear and the existing entity can be reused.
2. **Given** an entity has expenses, payments, and attachments, **When** the user opens entity aggregation, **Then** total expenses, total payments, remaining balance, transaction count, attachment count, latest date, history, category breakdown, and payment-method breakdown are shown.
3. **Given** two names normalize to the same identity in a workspace, **When** the user attempts to create the duplicate, **Then** the existing entity is reused or the user is clearly warned.

---

### User Story 4 - Export Complete Accounting Reports (Priority: P2)

Owners and accountants export separate and combined reports for expenses, payments, suppliers or entities, workers, contractors, daily activity, weekly activity, filtered views, and selected sections.

**Why this priority**: Reports are needed for reconciliation, stakeholder updates, and project documentation.

**Independent Test**: A user can generate each required export type with report title, project or workspace name, date range, generated date, applied filters, totals, section dividers, and attachment counts; empty data and generation failures are handled safely.

**Acceptance Scenarios**:

1. **Given** filtered expense and payment data exists, **When** the user exports a filtered report, **Then** the output includes only matching data and clearly lists the applied filters.
2. **Given** a user selects multiple report sections, **When** they export a combined report, **Then** every selected section appears once with consistent totals and section dividers.
3. **Given** no data exists for a requested report, **When** the user exports it, **Then** the app shows an empty report state or safe empty export without crashing.

---

### User Story 5 - Work Reliably Offline and at Scale (Priority: P1)

Users can continue creating and updating expense and payment activity during connectivity disruptions, and the system remains accurate and performant as transaction history grows.

**Why this priority**: Project teams often work on-site with unreliable connectivity, and incorrect totals or excessive loading cost directly harm accounting trust.

**Independent Test**: A user can create and update transactions offline, see pending items reflected in lists and supported summaries without double counting, and recover from failed sync or upload conditions.

**Acceptance Scenarios**:

1. **Given** the user is offline, **When** they create or update an expense or payment, **Then** the change is queued, visible where supported, and later syncs without duplication.
2. **Given** a queued action fails permanently, **When** the app detects the failure, **Then** the user sees a clear recoverable notice with no silent data loss.
3. **Given** the workspace has substantial historical data, **When** the user opens lists, dashboards, or aggregation views, **Then** normal screens use maintained summaries or scoped data and avoid unbounded historical reads.
4. **Given** the user exports a date-scoped report, **When** totals are calculated, **Then** the report may use bounded exact recalculation for the selected date range to preserve accounting accuracy.
5. **Given** a user lacks an accounting-approved role, **When** they try to view or export financial reports, entity balances, or attachments, **Then** access is denied with a clear message while permitted entry workflows remain available.

### Edge Cases

- Old records without attachments, entity IDs, entity types, payment status, or newer fields must load with fallback values.
- Duplicate entity names must be detected using normalized workspace-scoped names.
- Pending offline creates and updates must not be counted twice after successful sync.
- When the same transaction changes offline and remotely before sync completes, the last saved change must win automatically and the resulting record must remain internally consistent.
- Invalid file type, oversized file, missing local file, upload failure, save failure, sync failure, navigation failure, export failure, empty report data, no filter results, and no search results must produce visible recoverable feedback.
- Future-dated transactions must not enter current weekly summaries unless they fall inside the chosen date range.
- Large workspaces must not require loading all historical transactions for normal list, dashboard, weekly summary, or entity aggregation views.
- Attachment lists must display metadata and counts without loading full attachment images in list rows.
- Exported reports must remain usable when a selected section has no data.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support attachments for invoices, receipts, normal images, and PDF files across expenses, payments, suppliers or entities, workers, contractors, transport, equipment, and applicable accounting sections.
- **FR-002**: The system MUST validate attachment file type, size, and local availability before upload or save, and MUST store attachment metadata rather than embedded binary content in transaction records.
- **FR-003**: Authorized users MUST be able to open saved attachments, preview and zoom images, and open or download PDF attachments after saving, subject to the role restrictions in FR-031.
- **FR-004**: Expense and payment lists MUST show attachment indicators or counts without loading full attachment content in list rows.
- **FR-005**: The system MUST preserve existing attachments during edit unless the user explicitly removes or replaces them.
- **FR-006**: The system MUST support structured expense entry with category, supplier or entity, worker or contractor where applicable, purpose or description, amount, date, payment method, payment status, notes, project or workspace scope, and attachments.
- **FR-007**: The system MUST provide reusable suggestions for suppliers, vendors, workers, contractors, transport providers, equipment providers, and other entities.
- **FR-008**: Entity suggestions MUST be searchable, workspace-scoped, recent-first, and protected against duplicates using normalized names.
- **FR-009**: Creating or saving a transaction SHOULD NOT be blocked solely by entity suggestion sync failure; the transaction must retain typed entity metadata and surface a recoverable warning when needed.
- **FR-010**: Entity aggregation MUST show entity name, type, total expenses, total payments, total paid, remaining balance where applicable, transaction count, transaction history, attachment count, latest transaction date, category breakdown, and payment-method breakdown.
- **FR-011**: The dashboard MUST include a dedicated weekly section with weekly expenses, weekly payments or income where applicable, top entity, top category, labor summary, equipment summary, payment summary, recent weekly transactions, and weekly report export access.
- **FR-012**: Quick entry MUST allow fast mobile-friendly expense creation with date, category, entity, description or purpose, amount, payment method, payment status, notes, and attachments.
- **FR-013**: Quick entry MUST support save-and-add-another behavior while preserving useful repeated values and leaving the full expense form available.
- **FR-014**: The expenses page MUST support normal list display and grouping by exact date, relative date, category, entity, and payment method.
- **FR-015**: Each expense group MUST show title, total amount, transaction count, and an expandable or collapsible body.
- **FR-016**: Each expense row MUST show supplier or entity or worker name, category, amount, date, payment method, payment status, attachment count, and short description or notes.
- **FR-017**: Expense categories MUST include materials, labor, transport, equipment, storage, rentals, payments, and other, and each category view or grouping MUST show transaction count, total amount, and transaction details.
- **FR-018**: Expense filters MUST include search by supplier or entity name, worker name, description, and notes; date range; category; project; payment method; payment status; and entity or supplier or worker or contractor.
- **FR-019**: Payment filters MUST include search text; date range; project; payment method; payment status; and entity or supplier or worker or contractor where applicable.
- **FR-020**: Filtered lists MUST support active filter chips, clear-all behavior, no-results states, loading states, error states, and pagination-safe behavior.
- **FR-021**: The top of the expenses page MUST show today's total, current week total, current month total, and transaction count for the active project or workspace.
- **FR-022**: Offline expense and payment create and update actions MUST be queued, visible in supported lists and summaries, recoverable after failure, and protected from double counting.
- **FR-022a**: Offline sync conflict resolution MUST use last-saved-change-wins behavior while preserving transaction consistency, attachment state, and audit-relevant timestamps.
- **FR-023**: Attachment workflows MUST support offline save by preserving the transaction, local attachment references, pending upload status, and retry state until the files are uploaded and synced after reconnecting.
- **FR-024**: Normal list, dashboard, weekly summary, and aggregation views MUST avoid unbounded historical reads by using maintained summary records or scoped data access appropriate to large workspaces.
- **FR-024a**: Date-scoped reports MAY use bounded exact recalculation over the selected range when needed to preserve accounting accuracy.
- **FR-025**: PDF export MUST support expenses-only, payments-only, suppliers or entities, workers, contractors, daily, weekly, filtered, and combined multi-section reports.
- **FR-026**: Combined reports MUST allow users to select sections and MUST reuse the same definitions and calculations as separate reports.
- **FR-027**: Every report MUST include title, project or workspace name, date range, generated date, applied filters where applicable, totals, clear tables, section dividers, and attachment count indicators.
- **FR-028**: User-facing errors MUST be visible, understandable, recoverable, and present for attachment, save, sync, filter, search, dashboard, entity suggestion, entity aggregation, report, export, and navigation failures.
- **FR-029**: The implementation MUST include meaningful automated tests for attachments, validation, structured expense and payment save flows, quick entry, entity autocomplete, filters, grouping, collapsible sections, summaries, aggregation, weekly dashboard, PDF exports, offline merge, pagination, and query/index behavior where practical.
- **FR-030**: Previously working attachment, entity autocomplete, pagination, offline queue, dashboard, and report behavior MUST remain available unless explicitly replaced by equivalent or better behavior.
- **FR-031**: Financial reports, exports, entity balances, and attachments MUST be viewable or exportable only by workspace owners, admins, and accounting-approved roles; users without those roles MUST receive clear access feedback.

### Key Entities *(include if feature involves data)*

- **Attachment**: A supporting document or media file associated with an accounting record or entity; includes display name, file type, size, storage reference, access reference where available, upload date, uploader, and attachment category.
- **Expense**: A project or workspace cost record with structured accounting fields, related entity data, payment state, notes, attachments, and lifecycle state.
- **Payment**: A payment or income record with amount, date, method, status, related entity data, notes, attachments, and lifecycle state.
- **Entity**: A reusable workspace-scoped person or organization such as supplier, vendor, worker, contractor, transport provider, equipment provider, or other accounting party.
- **Entity Summary**: Aggregated financial and activity information for an entity, including totals, counts, balance, latest activity, attachment count, history, and breakdowns.
- **Category Summary**: Grouped accounting information for a category, including count, total, and transaction details.
- **Weekly Summary**: Current-week operational summary including totals, top entity, top category, labor, equipment, payments, and recent transactions.
- **Report Request**: A user's requested export type, date range, filters, selected sections, and target project or workspace.
- **Offline Action**: A queued create or update action awaiting sync, with enough identity and state information to merge into lists and summaries safely.
- **Access Role**: A workspace permission record that determines whether a user is an owner, admin, accounting-approved user, member, or entry-only user for financial reports, balances, exports, and attachments.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can create a fully structured expense with valid attachments in under 2 minutes on a mobile-sized screen.
- **SC-002**: A user can find a known expense or payment using combined search and filters in under 30 seconds.
- **SC-003**: Expense group totals, quick summary totals, entity aggregation totals, weekly dashboard totals, and exported report totals match the same filtered transaction set with 100% consistency in automated test fixtures.
- **SC-004**: At least 95% of normal list, filter, grouping, dashboard, and aggregation interactions complete without visible loading delay beyond 2 seconds using a representative dataset of at least 5 projects, 100 entities, 2,000 expenses, 1,000 payments, and 500 attachment metadata records.
- **SC-005**: All required export types can be generated for populated and empty data sets without crashing.
- **SC-006**: Offline-created or updated expense and payment actions appear once in supported list and summary views before sync and remain counted once after sync.
- **SC-007**: Invalid attachment, failed upload, failed save, failed sync, failed export, failed aggregation load, and no-results scenarios each show a clear recoverable user message.
- **SC-008**: Automated verification covers every original feature group with at least one meaningful passing test or a documented reason why the behavior requires manual verification.
- **SC-009**: No normal list, dashboard, weekly summary, or aggregation screen requires loading all historical transactions for a workspace as data volume grows.
- **SC-010**: Existing working expense, payment, attachment, entity autocomplete, offline queue, pagination, dashboard, and report workflows continue to pass regression tests.
- **SC-011**: Role-based access checks prevent unauthorized users from viewing or exporting financial reports, balances, and attachments in automated or manual verification.

## Assumptions

- The feature completes the existing product rather than replacing it.
- Existing data must remain backward-compatible and load safely when optional newer fields are absent.
- Mobile use is a primary workflow, so entry, filtering, grouping, and error recovery must work on small screens.
- Project or workspace scoping remains required for all accounting data, reports, summaries, and reusable entities.
- Financial totals should prioritize correctness and traceability over decorative UI.
- Contractor, equipment, worker accounting, and related sections are required scope even if their base screens or models need to be added.
