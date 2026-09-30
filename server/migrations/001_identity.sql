-- Up Migration
-- Identity & tenancy (data-model.md). Tasks T015.
-- Conventions: ids are the existing Firestore document ids (TEXT); user identity = Firebase uid;
-- timestamps are timestamptz set by the API; unmapped source fields are preserved in `legacy`.

CREATE TABLE workspaces (
  id          TEXT PRIMARY KEY,
  owner_uid   TEXT NOT NULL,
  name        TEXT NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy      JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX workspaces_owner_uid_idx ON workspaces (owner_uid);

-- Membership semantics match firestore.rules: a row existing means membership
-- (removal deletes the row). `status` is kept only as a guard; migrated rows without
-- a status default to 'active'. Id format: `${workspace_id}_${user_uid}` (membershipDocId).
CREATE TABLE memberships (
  id           TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  user_uid     TEXT NOT NULL,
  -- owner | admin | accountingApproved | member | entryOnly (AccountingAccessRoleType)
  role         TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'active',
  invited_by   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy       JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workspace_id, user_uid)
);
CREATE INDEX memberships_user_uid_idx ON memberships (user_uid);

-- Was users/{uid}. Credentials stay in Firebase Auth. Synced with `uid AS id`
-- (the sync service needs an `id`; generated columns are not replicated on Postgres 17).
CREATE TABLE user_profiles (
  uid                  TEXT PRIMARY KEY,
  email                TEXT,
  full_name            TEXT,
  photo_url            TEXT,
  active_workspace_id  TEXT REFERENCES workspaces (id) ON DELETE SET NULL,
  default_currency     TEXT,
  risk_alerts_enabled  BOOLEAN,
  setup_completed      BOOLEAN NOT NULL DEFAULT false,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy               JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- Was subscriptions/{workspaceId}, written by the RevenueCat webhook.
CREATE TABLE subscriptions (
  workspace_id     TEXT PRIMARY KEY REFERENCES workspaces (id) ON DELETE CASCADE,
  tier             TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'pro')),
  status           TEXT NOT NULL DEFAULT 'unknown',
  store            TEXT,
  is_auto_renewing BOOLEAN,
  trial_ends_at    TIMESTAMPTZ,
  period_ends_at   TIMESTAMPTZ,
  last_synced_at   TIMESTAMPTZ,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy           JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- Same document model as Firestore usage_counters:
--   `${workspaceId}_${YYYY-MM}` → monthly counts; `${workspaceId}_projects` → active projects.
CREATE TABLE usage_counters (
  id                   TEXT PRIMARY KEY,
  workspace_id         TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  period               TEXT NOT NULL,
  expenses_count       INTEGER NOT NULL DEFAULT 0 CHECK (expenses_count >= 0),
  payments_count       INTEGER NOT NULL DEFAULT 0 CHECK (payments_count >= 0),
  worker_entries_count INTEGER NOT NULL DEFAULT 0 CHECK (worker_entries_count >= 0),
  active_projects      INTEGER NOT NULL DEFAULT 0 CHECK (active_projects >= 0),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  legacy               JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workspace_id, period)
);

-- Server-only (never synced). Key = uid + function + X-Idempotency-Key.
CREATE TABLE idempotency_keys (
  key           TEXT PRIMARY KEY,
  uid           TEXT NOT NULL,
  function_name TEXT NOT NULL,
  response      JSONB NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idempotency_keys_created_at_idx ON idempotency_keys (created_at);

-- Server-only. RevenueCat event dedupe.
CREATE TABLE webhook_events (
  id           TEXT PRIMARY KEY,
  type         TEXT NOT NULL,
  workspace_id TEXT,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  payload      JSONB
);

-- Down Migration
DROP TABLE webhook_events;
DROP TABLE idempotency_keys;
DROP TABLE usage_counters;
DROP TABLE subscriptions;
DROP TABLE user_profiles;
DROP TABLE memberships;
DROP TABLE workspaces;
