-- Up Migration
-- Accounting core (data-model.md). Tasks T016.
-- Money: NUMERIC(14,2); the migrator flags source values with >2 decimals instead of rounding.
-- Attachments: kept as the same embedded JSON array Firestore stores on each record
-- (`[{id, fileName, downloadUrl, storagePath, uploadedAt, contentType, size, ...}]`), which is
-- what the client and the ported builders read. Metadata only, never file bytes.

CREATE TABLE projects (
  id                     TEXT PRIMARY KEY,
  workspace_id           TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  name                   TEXT NOT NULL,
  client_name            TEXT NOT NULL DEFAULT '',
  description            TEXT NOT NULL DEFAULT '',
  location               TEXT NOT NULL DEFAULT '',
  status                 TEXT NOT NULL DEFAULT 'active',
  contract_value         NUMERIC(14, 2),          -- optional (feature 003)
  budget_limit           NUMERIC(14, 2),
  start_date             TIMESTAMPTZ,
  expected_end_date      TIMESTAMPTZ,
  completion_percentage  NUMERIC(5, 2),
  is_archived            BOOLEAN NOT NULL DEFAULT false,
  archived_at            TIMESTAMPTZ,
  client_mutation_id     TEXT,
  created_by             TEXT,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy                 JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workspace_id, client_mutation_id)
);
CREATE INDEX projects_workspace_archived_idx ON projects (workspace_id, is_archived, updated_at DESC);

CREATE TABLE workers (
  id                 TEXT PRIMARY KEY,
  workspace_id       TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  name               TEXT NOT NULL,
  phone_number       TEXT NOT NULL DEFAULT '',
  worker_type        TEXT,
  billing_type       TEXT,
  daily_wage         NUMERIC(14, 2),
  status             TEXT NOT NULL DEFAULT 'active',
  notes              TEXT NOT NULL DEFAULT '',
  attachments        JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_archived        BOOLEAN NOT NULL DEFAULT false,
  client_mutation_id TEXT,
  created_by         TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy             JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workspace_id, client_mutation_id)
);
CREATE INDEX workers_workspace_idx ON workers (workspace_id, is_archived, name);

CREATE TABLE entities (
  id                 TEXT PRIMARY KEY,
  workspace_id       TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  type               TEXT NOT NULL,
  name               TEXT NOT NULL,
  normalized_name    TEXT NOT NULL DEFAULT '',
  phone_number       TEXT NOT NULL DEFAULT '',
  notes              TEXT NOT NULL DEFAULT '',
  default_rate       NUMERIC(14, 2),
  rate_unit          TEXT,
  attachments        JSONB NOT NULL DEFAULT '[]'::jsonb,
  last_used_at       TIMESTAMPTZ,
  is_archived        BOOLEAN NOT NULL DEFAULT false,
  client_mutation_id TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy             JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX entities_workspace_type_idx ON entities (workspace_id, type, normalized_name);
CREATE INDEX entities_workspace_last_used_idx ON entities (workspace_id, last_used_at DESC);

CREATE TABLE expenses (
  id                 TEXT PRIMARY KEY,
  workspace_id       TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id         TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  project_name       TEXT NOT NULL DEFAULT '',
  amount             NUMERIC(14, 2) NOT NULL,
  currency           TEXT NOT NULL DEFAULT 'EGP',
  date               TIMESTAMPTZ NOT NULL,
  -- EXPENSE_CATEGORIES in src/domain/money.ts ('labor' = legacy, merged into 'worker')
  category           TEXT NOT NULL DEFAULT 'other' CHECK (category IN (
                       'labor', 'worker', 'materials', 'equipment', 'transport',
                       'contractor', 'storage', 'rentals', 'payments', 'other')),
  description        TEXT NOT NULL DEFAULT '',
  notes              TEXT NOT NULL DEFAULT '',
  purpose            TEXT NOT NULL DEFAULT '',
  payment_method     TEXT NOT NULL DEFAULT '',
  payment_status     TEXT CHECK (payment_status IN ('unpaid', 'partial', 'paid', 'refunded', 'cancelled')),
  entity_id          TEXT,
  entity_type        TEXT,
  entity_name        TEXT,
  supplier_name      TEXT NOT NULL DEFAULT '',
  input_method       TEXT NOT NULL DEFAULT 'manual',
  source             TEXT NOT NULL DEFAULT '',
  transcript         TEXT NOT NULL DEFAULT '',
  storage_path       TEXT NOT NULL DEFAULT '',
  attachments        JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_archived        BOOLEAN NOT NULL DEFAULT false,
  archived_at        TIMESTAMPTZ,
  client_mutation_id TEXT,
  created_by         TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy             JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workspace_id, client_mutation_id)
);
CREATE INDEX expenses_project_date_idx ON expenses (workspace_id, project_id, date DESC);
CREATE INDEX expenses_workspace_date_idx ON expenses (workspace_id, is_archived, date DESC);
CREATE INDEX expenses_entity_idx ON expenses (workspace_id, entity_id) WHERE entity_id IS NOT NULL;

CREATE TABLE payments (
  id                 TEXT PRIMARY KEY,
  workspace_id       TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id         TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  amount             NUMERIC(14, 2) NOT NULL,
  paid_amount        NUMERIC(14, 2),
  date               TIMESTAMPTZ NOT NULL,
  description        TEXT NOT NULL DEFAULT '',
  notes              TEXT NOT NULL DEFAULT '',
  payment_method     TEXT NOT NULL DEFAULT '',
  payment_status     TEXT CHECK (payment_status IN ('unpaid', 'partial', 'paid', 'refunded', 'cancelled')),
  entity_id          TEXT,
  entity_type        TEXT,
  entity_name        TEXT,
  attachments        JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_archived        BOOLEAN NOT NULL DEFAULT false,
  archived_at        TIMESTAMPTZ,
  client_mutation_id TEXT,
  created_by         TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy             JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workspace_id, client_mutation_id)
);
CREATE INDEX payments_project_date_idx ON payments (workspace_id, project_id, date DESC);
CREATE INDEX payments_workspace_date_idx ON payments (workspace_id, is_archived, date DESC);

CREATE TABLE worker_entries (
  id                 TEXT PRIMARY KEY,
  workspace_id       TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id         TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  worker_id          TEXT REFERENCES workers (id) ON DELETE SET NULL,
  date               TIMESTAMPTZ NOT NULL,
  days_worked        NUMERIC(8, 2),
  daily_wage         NUMERIC(14, 2),
  total_cost         NUMERIC(14, 2),            -- NULL on legacy rows; derived by workerEntryTotalCost
  status             TEXT,
  notes              TEXT NOT NULL DEFAULT '',
  attachments        JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_archived        BOOLEAN NOT NULL DEFAULT false,
  archived_at        TIMESTAMPTZ,
  client_mutation_id TEXT,
  created_by         TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy             JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workspace_id, client_mutation_id)
);
CREATE INDEX worker_entries_project_date_idx ON worker_entries (workspace_id, project_id, date DESC);
CREATE INDEX worker_entries_worker_idx ON worker_entries (workspace_id, worker_id, date DESC);

-- Four accounting-record families share one shape; the party columns differ per family.
CREATE TABLE worker_accounting_records (
  id              TEXT PRIMARY KEY,
  workspace_id    TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id      TEXT REFERENCES projects (id) ON DELETE CASCADE,
  worker_id       TEXT,
  worker_name     TEXT,
  amount          NUMERIC(14, 2) NOT NULL,
  paid_amount     NUMERIC(14, 2),
  date            TIMESTAMPTZ NOT NULL,
  description     TEXT NOT NULL DEFAULT '',
  notes           TEXT NOT NULL DEFAULT '',
  payment_method  TEXT NOT NULL DEFAULT '',
  payment_status  TEXT,
  attachments     JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_archived     BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy          JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX worker_accounting_records_worker_idx ON worker_accounting_records (workspace_id, worker_id, date DESC);

CREATE TABLE contractor_accounting_records (
  id              TEXT PRIMARY KEY,
  workspace_id    TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id      TEXT REFERENCES projects (id) ON DELETE CASCADE,
  contractor_id   TEXT,
  contractor_name TEXT,
  amount          NUMERIC(14, 2) NOT NULL,
  date            TIMESTAMPTZ NOT NULL,
  description     TEXT NOT NULL DEFAULT '',
  notes           TEXT NOT NULL DEFAULT '',
  payment_method  TEXT NOT NULL DEFAULT '',
  payment_status  TEXT,
  attachments     JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_archived     BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy          JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX contractor_accounting_records_party_idx ON contractor_accounting_records (workspace_id, contractor_id, date DESC);

CREATE TABLE equipment_accounting_records (
  id              TEXT PRIMARY KEY,
  workspace_id    TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id      TEXT REFERENCES projects (id) ON DELETE CASCADE,
  provider_id     TEXT,
  provider_name   TEXT,
  amount          NUMERIC(14, 2) NOT NULL,
  date            TIMESTAMPTZ NOT NULL,
  description     TEXT NOT NULL DEFAULT '',
  notes           TEXT NOT NULL DEFAULT '',
  payment_method  TEXT NOT NULL DEFAULT '',
  payment_status  TEXT,
  attachments     JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_archived     BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy          JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX equipment_accounting_records_party_idx ON equipment_accounting_records (workspace_id, provider_id, date DESC);

CREATE TABLE transport_provider_accounting_records (
  id              TEXT PRIMARY KEY,
  workspace_id    TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  project_id      TEXT REFERENCES projects (id) ON DELETE CASCADE,
  provider_id     TEXT,
  provider_name   TEXT,
  amount          NUMERIC(14, 2) NOT NULL,
  date            TIMESTAMPTZ NOT NULL,
  description     TEXT NOT NULL DEFAULT '',
  notes           TEXT NOT NULL DEFAULT '',
  payment_method  TEXT NOT NULL DEFAULT '',
  payment_status  TEXT,
  attachments     JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_archived     BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy          JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX transport_accounting_records_party_idx ON transport_provider_accounting_records (workspace_id, provider_id, date DESC);

-- Firestore `attachments` collection (financial-only reads in firestore.rules). Carried over
-- as-is; record attachments live in each record's `attachments` array above.
CREATE TABLE attachments (
  id           TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy       JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE notifications (
  id             TEXT PRIMARY KEY,
  workspace_id   TEXT REFERENCES workspaces (id) ON DELETE CASCADE,
  target_user_id TEXT NOT NULL,
  type           TEXT,
  title          TEXT NOT NULL DEFAULT '',
  message        TEXT NOT NULL DEFAULT '',
  read_at        TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy         JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX notifications_target_idx ON notifications (target_user_id, created_at DESC);

-- Server-only today (`allow read, write: if false`).
CREATE TABLE drafts (
  id           TEXT PRIMARY KEY,
  workspace_id TEXT REFERENCES workspaces (id) ON DELETE CASCADE,
  uid          TEXT,
  payload      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE reports (
  id           TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  payload      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE report_exports (
  id           TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  payload      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Down Migration
DROP TABLE report_exports;
DROP TABLE reports;
DROP TABLE drafts;
DROP TABLE notifications;
DROP TABLE attachments;
DROP TABLE transport_provider_accounting_records;
DROP TABLE equipment_accounting_records;
DROP TABLE contractor_accounting_records;
DROP TABLE worker_accounting_records;
DROP TABLE worker_entries;
DROP TABLE payments;
DROP TABLE expenses;
DROP TABLE entities;
DROP TABLE workers;
DROP TABLE projects;
