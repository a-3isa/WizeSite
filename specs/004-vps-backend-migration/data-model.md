# Data Model: Firestore → PostgreSQL

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Date**: 2026-09-30

## Conventions (apply to every table)

| Concern | Rule |
|---|---|
| Primary key | `id TEXT` = the existing Firestore document ID (migrated) or a client/server-generated ID in the same format (new). Never renumbered. |
| User identity | `*_uid TEXT` = Firebase Auth `uid`. No local users table for credentials. |
| Workspace scoping | Every workspace-owned table has `workspace_id TEXT NOT NULL REFERENCES workspaces(id)` and an index leading with it. This is the unit of authorization and of sync. |
| Money | `NUMERIC(14,2)`. Migrator flags any source double with more than 2 decimal places (Constitution II: no silent rounding). Client keeps `double` as today. RPCs refuse money/quantity inputs with more than 2 decimals (`invalid-argument`) instead of letting Postgres round; the app's inputs never send more. Exception: `worker_entries.total_cost` is `NUMERIC(18,4)` (days × wage, both 2-decimal, is exact at 4; migration 005). |
| Timestamps | `timestamptz` UTC. `created_at`, `updated_at` (set by API, never client clock) on every table. Firestore `Timestamp` → exact microsecond value. |
| Archive | `is_archived BOOLEAN NOT NULL DEFAULT false` where the model has it today; archiving is a state change, not a delete. |
| Hard deletes | Only project cascade delete and account deletion. PowerSync propagates deletes to devices. |
| Idempotency | `client_mutation_id TEXT` kept where it exists today; `UNIQUE (workspace_id, client_mutation_id)` where non-null. |
| Unknown legacy fields | `legacy JSONB` holds any source field not mapped to a column, so nothing is silently dropped. |
| Sync `id` | Every synced table has a TEXT `id` column (PowerSync requirement). Tables keyed by something else (`user_profiles.uid`, `subscriptions.workspace_id`, `project_metrics.project_id`, `workspace_metrics.workspace_id`) alias it in the sync rules (`SELECT uid AS id, ...`). Generated columns are not used: Postgres 17 logical replication does not publish them. |
| Authoritative schema | `server/migrations/*.sql`. This document explains it; where they differ, the migrations win. |
| Enums | `TEXT` + `CHECK` using the lists in `functions/src/money.ts` (payment statuses, expense categories). |

## Identity & tenancy

### workspaces
`id`, `name`, `owner_uid`, `created_at`, `updated_at`, `legacy`.

### memberships
`id`, `workspace_id` → workspaces, `user_uid`, `role` (TEXT; financial access for `owner`, `admin`, `accountingApproved`, as in
`canAccessAccounting` in `firestore.rules`; any other value = ordinary member), `status`, `invited_by`, timestamps.
UNIQUE (`workspace_id`, `user_uid`). Drives both API authorization and sync-rule bucketing.
**Semantics match today's rules: a row existing = membership; removing a member deletes the row.** `status`
defaults to `'active'` (functions only ever write `"active"`); the migrator sets it for rows that lack it.

### user_profiles (was `users/{uid}`)
PK `uid`, `email`, `full_name`, `photo_url`, `active_workspace_id` (was `workspaceId`), `default_currency`,
`risk_alerts_enabled`, `setup_completed`, timestamps (fields of `UserSettings`).
Credentials and sign-in methods stay in Firebase Auth.

### subscriptions (was `subscriptions/{workspaceId}`)
PK `workspace_id`, `tier` (`free|pro`), `status`, `store`, `is_auto_renewing`, `trial_ends_at`, `period_ends_at`,
`last_synced_at` — exactly the fields the RevenueCat webhook writes today.

### usage_counters
Same document model as Firestore: PK `id` = `${workspaceId}_${YYYY-MM}` (monthly `expenses_count`, `payments_count`,
`worker_entries_count`) or `${workspaceId}_projects` (`active_projects`); `workspace_id`, `period`; every count
`CHECK (>= 0)`. Limits are not stored (they come from `FREE_LIMITS` + subscription tier, as today). Updated in the
same transaction as the create/archive RPC (quota + refund).

### idempotency_keys
PK `key`, `uid`, `function_name`, `response JSONB`, `created_at`. TTL purge after 30 days.

### webhook_events
PK `id` (RevenueCat event id), `type`, `workspace_id`, `received_at`, `payload JSONB`. Dedupe for FR-007.

## Accounting core

### projects
`id`, `workspace_id`, `name`, `client_name`, `description`, `location`, `status`,
`contract_value NUMERIC(14,2) NULL` (optional per feature 003), `budget_limit NUMERIC(14,2) NULL`,
`start_date`, `expected_end_date`, `completion_percentage DOUBLE PRECISION` (a progress figure, not money: stored exactly as Firestore held it, never rounded or precision-flagged; migration 004), `is_archived`, `client_mutation_id`, timestamps, `legacy`.
Derived fields (`total_expenses`, `total_payments`, `total_income`, `net`, `net_profit`) are **not**
stored here; they live in `project_metrics` (single source of truth). The client model reads them
through a view/join as today.

### expenses
`id`, `workspace_id`, `project_id` → projects, `amount`, `currency`, `date`, `category` (CHECK), `description`,
`notes`, `purpose`, `payment_method`, `payment_status` (CHECK), `entity_id`, `entity_type`, `entity_name`,
`supplier_name`, `input_method`, `source`, `transcript`, `is_archived`, `client_mutation_id`, timestamps, `legacy`.
Index (`workspace_id`, `project_id`, `date DESC`).

### payments
`id`, `workspace_id`, `project_id`, `amount`, `paid_amount`, `date`, `description`, `notes`, `payment_method`,
`payment_status`, `entity_id`, `entity_type`, `entity_name`, `is_archived`, `client_mutation_id`, timestamps, `legacy`.
Invariant (from feature 003): API rejects a payment on a project whose `contract_value IS NULL`.

### workers
`id`, `workspace_id`, `name`, `phone_number`, `worker_type`, `billing_type`, `daily_wage`, `status`, `is_archived`, timestamps.

### worker_entries
`id`, `workspace_id`, `project_id`, `worker_id` → workers, `date`, `days_worked`, `daily_wage`, `total_cost`,
`notes`, `is_archived`, `client_mutation_id`, timestamps.

### worker_accounting_records, contractor_accounting_records, equipment_accounting_records, transport_provider_accounting_records
Same shape family: `id`, `workspace_id`, `project_id`, `entity_id`, `amount`, `paid_amount`, `date`, `status`,
`notes`, `is_archived`, timestamps, `legacy`. (Exact columns copied from each Dart record model during
implementation; today these are written directly by the client — moving to RPC per research R3.)

### entities
Resource directory (suppliers, contractors, equipment, transport providers): `id`, `workspace_id`,
`entity_type`, `name`, `phone`, `notes`, `last_used_at`, `is_archived`, timestamps, `legacy`.
UNIQUE (`workspace_id`, `entity_type`, lower(`name`)) if today's dedupe logic in `entity_repository.dart` requires it.

### Record attachments (metadata only — Constitution: never binary in DB)
**Decision (implementation, 2026-09-30): kept as the embedded `attachments JSONB` array on each record**, the same
`[{id, fileName, downloadUrl, storagePath, uploadedAt, contentType, size, ...}]` shape Firestore stores. The client and
the ported builders read that shape, so no translation layer is needed and the rollback mapping is a straight copy.
(The earlier plan to normalise into a separate table was dropped: it added a join everywhere for no user value.)

### attachments table
Mirrors the separate Firestore `attachments` collection (financial-only reads); carried over as-is (`legacy`).

## Derived (maintained in-transaction by the API — research R6)

Each derived table stores the builder output as `payload JSONB`, exactly the document shape the ported
`src/domain/accounting.ts` produces (nested `categoryTotals`, `monthlyFlow`, `topWorkers`, ...), with only keys and a
few filter columns (`workspace_id`, `project_id`, `risk_level`) broken out.

| Table | Key | Recomputed when |
|---|---|---|
| `project_metrics` | `project_id` | any expense/payment/worker_entry/accounting-record/project change in that project |
| `workspace_metrics` | `workspace_id` | any project_metrics change in the workspace |
| `project_summaries` | `id` = id produced by `buildAccountingSummaryPayloads` today | same as project_metrics |
| `weekly_summaries` | `id` as today; scoped by (`workspace_id`, `project_id`) | same as project_metrics (scoped replace) |
| `entity_summaries` | `id` as today; scoped by (`workspace_id`, `project_id`) | same as project_metrics (scoped replace) |
| `category_summaries` | `id` as today; scoped by (`workspace_id`, `project_id`) | same as project_metrics (scoped replace) |
| `worker_accounting_summaries` | `worker_id` | worker_entry / worker_accounting_record change |

Decision: **one table per Firestore summary collection**, not a merged table. This keeps the ids and
shapes `buildAccountingSummaryPayloads` produces and the client reads (`project_summaries` in
`expense_summary_providers.dart`, `entity_summaries` in `entity_aggregation_providers.dart`), so
neither the ported builders nor the client ports need a translation layer. "Scoped replace" means:
delete rows for (`workspace_id`, `project_id`) not in the new set, then upsert the new set, exactly
like `replaceScopedSummaryDocs` today.

Each carries `computed_at` and `source_version` (monotonic) so the nightly reconciler can detect drift.
Risk classification (`classifyProjectRisk`) stored on `project_metrics.risk_level`.

## Other

- `notifications`: `id`, `workspace_id`, `recipient_uid`, `type`, `payload JSONB`, `read_at`, `created_at`.
- `drafts` (voice drafts): `id`, `workspace_id`, `uid`, `payload JSONB`, `audio_path`, timestamps.
- `reports`, `report_exports`: carried over only if non-empty in production (migrator reports counts; empty ⇒ table created, no data).

## Rollback support

### deleted_rows (tombstones)
`id BIGSERIAL`, `table_name TEXT`, `row_id TEXT`, `workspace_id TEXT NULL`, `deleted_at timestamptz`.
Populated by an AFTER DELETE trigger on every base (non-derived) table, created in
`004_tombstones.sql`. Used only by the rollback tool during the 7-day window (FR-016); purged with
a TTL of 30 days. Not synced to devices.

### Reverse mapping (rollback)

Used by `server/tools/rollback-to-firestore` to write changes made after `cutover_at` back to Firestore:

| Postgres | → Firestore | Rule |
|---|---|---|
| base table row (`updated_at > cutover_at`) | same collection, doc id = `id` | snake_case → the camelCase field names in the Dart models; `timestamptz` → `Timestamp`; `NUMERIC` → number |
| `legacy jsonb` | merged into the doc | legacy keys written first, mapped columns override on conflict |
| record `attachments` JSONB array | the record's embedded `attachments[]` | copied as-is (same element shape) |
| `user_profiles.settings` | `users/{uid}` settings sub-map | |
| `deleted_rows` entry | delete doc `table_name/row_id` | |
| derived tables (`project_metrics`, `*_summaries`, `workspace_metrics`, `worker_accounting_summaries`) | **not written** | recomputed by the redeployed `on*WriteRecompute` triggers when the base docs land; the rollback tool then touches each affected project doc once to force a recompute |
| new files under `$FILES_ROOT` | same path in Firebase Storage | MD5 verified after upload |

## State transitions

- **Record** (expense, payment, worker_entry, accounting records): `active → archived` (quota refund,
  metrics recompute) `→ active` only where an unarchive RPC exists today. Hard delete only via project cascade.
- **Project**: `active ⇄ archived`; `→ deleted` via `deleteProjectCascade` (deletes children, attachments files,
  metrics; refunds counters).
- **Membership**: `invited → active → removed`.
- **Account**: `active → deleted` (`deleteOwnAccount`): Postgres rows owned by uid + files deleted in one
  job, then Firebase Auth user deleted; idempotent on retry.

## Client local schema (PowerSync SQLite)

Mirrors the synced server tables with the same column names (PowerSync stores rows as views over JSON;
money as REAL, timestamps as ISO text). Local-only tables: none — the Hive `OfflineActionQueue` and
`PendingAttachmentService` stay in Hive. Optimistic display of queued writes is unchanged (existing
pending-record overlay logic).

## Migration mapping summary

| Firestore collection | → Table | Notes |
|---|---|---|
| users | user_profiles | settings sub-map → `settings` jsonb |
| workspaces, memberships | same | |
| projects | projects (+ project_metrics for derived fields) | derived totals re-computed, compared in report |
| expenses, payments, worker_entries, workers, entities | same | embedded `attachments[]` → attachments table |
| *_accounting_records (4) | same | |
| project_metrics, workspace_metrics, worker_accounting_summaries, *_summaries | recomputed, not copied | source values kept only in verification report |
| subscriptions, usage_counters | same | |
| idempotency_keys | not migrated | old keys irrelevant after cutover (queue must be empty) |
| webhook_events | copied (dedupe history) | |
| notifications, drafts, reports, report_exports | same if non-empty | |
| Storage `receipts/`, `attachments/`, `voice-expenses/`, `profile-photos/` | `/srv/wizesite/files/<same path>` | MD5 verified |
