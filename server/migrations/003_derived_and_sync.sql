-- Up Migration
-- Derived state + sync publication (data-model.md "Derived"). Tasks T017.
-- Derived rows are recomputed in the same transaction as the mutating RPC (research R6).
-- `payload` holds exactly the document the ported builders in src/domain/accounting.ts produce
-- (nested categoryTotals, monthlyFlow, topWorkers, ...), so client parsing and parity checks see
-- the same shape Firestore stored. A few keys are broken out as columns for filtering.

CREATE TABLE project_metrics (
  project_id     TEXT PRIMARY KEY REFERENCES projects (id) ON DELETE CASCADE,
  workspace_id   TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  risk_level     TEXT,
  payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
  source_version BIGINT NOT NULL DEFAULT 0,
  computed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX project_metrics_workspace_idx ON project_metrics (workspace_id);

CREATE TABLE workspace_metrics (
  workspace_id   TEXT PRIMARY KEY REFERENCES workspaces (id) ON DELETE CASCADE,
  payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
  source_version BIGINT NOT NULL DEFAULT 0,
  computed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One table per Firestore summary collection; ids are the ones buildAccountingSummaryPayloads
-- produces. weekly/entity/category rows use "scoped replace" per (workspace_id, project_id).
CREATE TABLE project_summaries (
  id             TEXT PRIMARY KEY,
  workspace_id   TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id     TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
  computed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX project_summaries_scope_idx ON project_summaries (workspace_id, project_id);

CREATE TABLE weekly_summaries (
  id             TEXT PRIMARY KEY,
  workspace_id   TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id     TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
  computed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX weekly_summaries_scope_idx ON weekly_summaries (workspace_id, project_id);

CREATE TABLE entity_summaries (
  id             TEXT PRIMARY KEY,
  workspace_id   TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id     TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
  computed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX entity_summaries_scope_idx ON entity_summaries (workspace_id, project_id);

CREATE TABLE category_summaries (
  id             TEXT PRIMARY KEY,
  workspace_id   TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id     TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
  computed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX category_summaries_scope_idx ON category_summaries (workspace_id, project_id);

CREATE TABLE worker_accounting_summaries (
  id             TEXT PRIMARY KEY,
  workspace_id   TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  worker_id      TEXT,
  payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
  computed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX worker_accounting_summaries_worker_idx ON worker_accounting_summaries (workspace_id, worker_id);

-- Logical-replication publication read by the PowerSync service (contracts/sync-rules.md).
-- Server-only tables (idempotency_keys, webhook_events, drafts) are deliberately excluded.
CREATE PUBLICATION powersync FOR TABLE
  workspaces, memberships, user_profiles, subscriptions, usage_counters,
  projects, workers, entities, expenses, payments, worker_entries,
  worker_accounting_records, contractor_accounting_records,
  equipment_accounting_records, transport_provider_accounting_records,
  attachments, notifications, reports, report_exports,
  project_metrics, workspace_metrics, project_summaries, weekly_summaries,
  entity_summaries, category_summaries, worker_accounting_summaries;

-- Down Migration
DROP PUBLICATION powersync;
DROP TABLE worker_accounting_summaries;
DROP TABLE category_summaries;
DROP TABLE entity_summaries;
DROP TABLE weekly_summaries;
DROP TABLE project_summaries;
DROP TABLE workspace_metrics;
DROP TABLE project_metrics;
