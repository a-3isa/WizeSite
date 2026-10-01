-- Up Migration
-- Rollback support (data-model.md "Rollback support", tasks.md T099). During the 7-day window
-- after cutover the rollback tool copies every base-table change made on the VPS back to
-- Firestore, so it needs (1) a reliable updated_at on every change and (2) a record of deletes.

-- (1) Every update bumps updated_at, even from a code path that forgot to set it. A statement that
-- sets updated_at itself keeps its value.
CREATE FUNCTION touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.updated_at IS NOT DISTINCT FROM OLD.updated_at THEN
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END;
$$;

-- (2) Tombstones: one row per deleted base row. Not synced to devices. Kept 30 days.
CREATE TABLE deleted_rows (
  id           BIGSERIAL PRIMARY KEY,
  table_name   TEXT NOT NULL,
  row_id       TEXT NOT NULL,
  workspace_id TEXT,
  deleted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX deleted_rows_deleted_at_idx ON deleted_rows (deleted_at);

-- TG_ARGV[0]: the key column that is the Firestore document id.
CREATE FUNCTION record_deleted_row() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  old_row jsonb := to_jsonb(OLD);
BEGIN
  INSERT INTO deleted_rows (table_name, row_id, workspace_id)
  VALUES (TG_TABLE_NAME, old_row ->> TG_ARGV[0], old_row ->> 'workspace_id');
  RETURN OLD;
END;
$$;

DO $$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('workspaces', 'id'), ('memberships', 'id'), ('user_profiles', 'uid'),
      ('subscriptions', 'workspace_id'), ('usage_counters', 'id'),
      ('projects', 'id'), ('workers', 'id'), ('entities', 'id'),
      ('expenses', 'id'), ('payments', 'id'), ('worker_entries', 'id'),
      ('worker_accounting_records', 'id'), ('contractor_accounting_records', 'id'),
      ('equipment_accounting_records', 'id'), ('transport_provider_accounting_records', 'id'),
      ('attachments', 'id'), ('notifications', 'id'), ('drafts', 'id'),
      ('reports', 'id'), ('report_exports', 'id')
    ) AS v(table_name, key_column)
  LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION touch_updated_at()',
      t.table_name || '_touch_updated_at', t.table_name);
    EXECUTE format(
      'CREATE TRIGGER %I AFTER DELETE ON %I FOR EACH ROW EXECUTE FUNCTION record_deleted_row(%L)',
      t.table_name || '_tombstone', t.table_name, t.key_column);
  END LOOP;
END;
$$;

-- Down Migration

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'workspaces', 'memberships', 'user_profiles', 'subscriptions', 'usage_counters',
    'projects', 'workers', 'entities', 'expenses', 'payments', 'worker_entries',
    'worker_accounting_records', 'contractor_accounting_records', 'equipment_accounting_records',
    'transport_provider_accounting_records', 'attachments', 'notifications', 'drafts', 'reports',
    'report_exports'
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_touch_updated_at', t);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_tombstone', t);
  END LOOP;
END;
$$;
DROP FUNCTION record_deleted_row();
DROP FUNCTION touch_updated_at();
DROP TABLE deleted_rows;
