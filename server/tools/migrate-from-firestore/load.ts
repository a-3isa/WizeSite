/**
 * Loads transformed rows into Postgres (tasks.md T037). One transaction for the whole migration
 * (two users' data is small), so any failure leaves the database untouched. Derived tables are
 * recomputed from the loaded base rows, never copied.
 */
import type { Sql } from "../../src/db/pool";
import { recomputeProject, recomputeWorkerAccounting } from "../../src/recompute/persist";
import type { Row, TableColumns } from "./transform";

/** Insert order satisfies every foreign key in migrations/*.sql. */
export const LOAD_ORDER = [
  "workspaces",
  "user_profiles",
  "memberships",
  "subscriptions",
  "usage_counters",
  "webhook_events",
  "projects",
  "workers",
  "entities",
  "expenses",
  "payments",
  "worker_entries",
  "worker_accounting_records",
  "contractor_accounting_records",
  "equipment_accounting_records",
  "transport_provider_accounting_records",
  "attachments",
  "notifications",
  "drafts",
  "reports",
  "report_exports",
];

const JSON_COLUMNS = new Set(["legacy", "attachments", "payload"]);

/** Hard references checked before insert: table.column -> referenced table. */
const REFERENCES: Array<[string, string, string]> = [
  ["memberships", "workspace_id", "workspaces"],
  ["subscriptions", "workspace_id", "workspaces"],
  ["usage_counters", "workspace_id", "workspaces"],
  ["projects", "workspace_id", "workspaces"],
  ["workers", "workspace_id", "workspaces"],
  ["entities", "workspace_id", "workspaces"],
  ["expenses", "project_id", "projects"],
  ["payments", "project_id", "projects"],
  ["worker_entries", "project_id", "projects"],
];

export async function readTableColumns(sql: Sql): Promise<TableColumns> {
  const rows = await sql<{ table_name: string; column_name: string }[]>`
    SELECT table_name, column_name FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name <> 'pgmigrations'`;
  const columns: TableColumns = new Map();
  for (const r of rows) {
    if (!columns.has(r.table_name)) columns.set(r.table_name, new Set());
    columns.get(r.table_name)!.add(r.column_name);
  }
  return columns;
}

function keyOf(table: string, row: Row): string {
  return `${table === "user_profiles" ? row.uid : table === "subscriptions" ? row.workspace_id : row.id}`;
}

export function findOrphans(rows: Map<string, Row[]>): string[] {
  const ids = new Map<string, Set<string>>();
  for (const [table, list] of rows) ids.set(table, new Set(list.map((r) => keyOf(table, r))));
  const orphans: string[] = [];
  for (const [table, column, target] of REFERENCES) {
    for (const row of rows.get(table) ?? []) {
      const ref = row[column];
      if (ref == null || ref === "") continue;
      if (!ids.get(target)?.has(`${ref}`)) {
        orphans.push(`${table}/${keyOf(table, row)}.${column} -> ${target}/${ref} (missing)`);
      }
    }
  }
  return orphans;
}

export interface LoadResult {
  loaded: Map<string, number>;
  recomputedProjects: number;
}

export async function loadMigration(
  sql: Sql,
  rows: Map<string, Row[]>,
  options: { reset?: boolean; now?: Date } = {},
): Promise<LoadResult> {
  const orphans = findOrphans(rows);
  if (orphans.length > 0) {
    throw new Error(`Refusing to load: orphaned references:\n  ${orphans.join("\n  ")}`);
  }

  // A soft reference: point a user at no workspace rather than at one that was skipped.
  const workspaceIds = new Set((rows.get("workspaces") ?? []).map((w) => `${w.id}`));
  for (const profile of rows.get("user_profiles") ?? []) {
    if (profile.active_workspace_id != null && !workspaceIds.has(`${profile.active_workspace_id}`)) {
      profile.active_workspace_id = null;
    }
  }

  // Firestore treats an explicit null like a missing field, and so does the app. For NOT NULL
  // columns with a default, leave such a value out so Postgres applies the default; a null in a
  // required column without one still fails the load.
  const defaulted = new Set(
    (
      await sql<{ table_name: string; column_name: string }[]>`
        SELECT table_name, column_name FROM information_schema.columns
        WHERE table_schema = 'public' AND is_nullable = 'NO' AND column_default IS NOT NULL`
    ).map((r) => `${r.table_name}.${r.column_name}`),
  );

  const loaded = new Map<string, number>();
  let recomputedProjects = 0;
  await sql.begin(async (tx) => {
    const t = tx as unknown as Sql;
    const [{ count }] = await t<{ count: string }[]>`SELECT count(*) FROM workspaces`;
    if (Number(count) > 0) {
      if (!options.reset) {
        throw new Error("Target database is not empty; re-run with --reset to replace its contents.");
      }
      await t.unsafe(`TRUNCATE ${[...LOAD_ORDER].reverse().map((x) => `"${x}"`).join(", ")},
        project_metrics, workspace_metrics, project_summaries, weekly_summaries,
        entity_summaries, category_summaries, worker_accounting_summaries CASCADE`);
    }

    for (const table of LOAD_ORDER) {
      const list = rows.get(table) ?? [];
      for (const row of list) {
        const values: Record<string, unknown> = {};
        for (const [column, value] of Object.entries(row)) {
          if (value === null && defaulted.has(`${table}.${column}`)) continue;
          values[column] = JSON_COLUMNS.has(column) ? t.json(value as never) : value;
        }
        await t`INSERT INTO ${t(table)} ${t(values as never)}`;
      }
      loaded.set(table, list.length);
    }

    for (const project of rows.get("projects") ?? []) {
      await recomputeProject(t, `${project.workspace_id}`, `${project.id}`, options.now);
      recomputedProjects++;
    }
    const workerKeys = new Set(
      (rows.get("worker_accounting_records") ?? [])
        .filter((r) => r.worker_id)
        .map((r) => `${r.workspace_id}\u0000${r.worker_id}`),
    );
    for (const key of workerKeys) {
      const [workspaceId, workerId] = key.split("\u0000");
      await recomputeWorkerAccounting(t, workspaceId, workerId);
    }
  });
  return { loaded, recomputedProjects };
}
