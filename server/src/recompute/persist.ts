import type { Sql } from "../db/pool";
import {
  buildWorkerAccountingSummaryPayload,
  buildWorkspaceMetricsPayload,
  type TriggerDocData,
} from "../domain/accounting";
import { computeProjectDerived } from "./project";
import { rowToDoc } from "./rows";

/**
 * Persists derived state (research R6: recomputed in the same transaction as the mutation).
 * Ports recomputeProjectSummary / writeAccountingSummaries / replaceScopedSummaryDocs /
 * recomputeWorkspaceMetrics / recomputeWorkerAccountingSummary from functions/src/index.ts.
 * Writes only when the payload changed (writeIfChanged), so idle recomputes do not churn sync.
 */

type Row = Record<string, unknown>;

/** JSON round-trip so Dates become ISO strings exactly as they are stored in jsonb. */
function toJson<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

/** jsonb does not preserve object key order, so compare with keys sorted at every level. */
function canonical(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(canonical);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value as Record<string, unknown>)
        .sort()
        .map((key) => [key, canonical((value as Record<string, unknown>)[key])]),
    );
  }
  return value;
}

function sameJson(a: unknown, b: unknown): boolean {
  return JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
}

export async function recomputeProject(
  sql: Sql,
  workspaceId: string,
  projectId: string,
  now: Date = new Date(),
): Promise<void> {
  const [project] = await sql<Row[]>`
    SELECT * FROM projects WHERE id = ${projectId} AND workspace_id = ${workspaceId}`;
  if (!project) {
    return;
  }
  const [expenses, payments, workerEntries] = await Promise.all([
    sql<Row[]>`SELECT * FROM expenses
               WHERE workspace_id = ${workspaceId} AND project_id = ${projectId} AND NOT is_archived`,
    sql<Row[]>`SELECT * FROM payments
               WHERE workspace_id = ${workspaceId} AND project_id = ${projectId} AND NOT is_archived`,
    sql<Row[]>`SELECT * FROM worker_entries
               WHERE workspace_id = ${workspaceId} AND project_id = ${projectId} AND NOT is_archived`,
  ]);
  const workerIds = [
    ...new Set(workerEntries.map((e) => `${e.worker_id ?? ""}`.trim()).filter(Boolean)),
  ];
  const workers =
    workerIds.length === 0
      ? []
      : await sql<{ id: string; name: string }[]>`
          SELECT id, name FROM workers WHERE workspace_id = ${workspaceId} AND id IN ${sql(workerIds)}`;

  const derived = computeProjectDerived({
    workspaceId,
    projectId,
    project: rowToDoc(project),
    expenses: expenses.map(rowToDoc),
    payments: payments.map(rowToDoc),
    workerEntries: workerEntries.map(rowToDoc),
    workerNames: new Map(workers.map((w) => [w.id, w.name])),
    now,
  });

  await writeProjectMetrics(sql, workspaceId, projectId, toJson(derived.projectMetrics));

  const { summaries } = derived;
  const { id: projectSummaryId, ...projectSummary } = summaries.projectSummary as TriggerDocData;
  await upsertSummary(sql, "project_summaries", `${projectSummaryId ?? ""}`, workspaceId, projectId, projectSummary);
  await replaceScopedSummaries(sql, "weekly_summaries", workspaceId, projectId, summaries.weeklySummaries);
  await replaceScopedSummaries(sql, "entity_summaries", workspaceId, projectId, summaries.entitySummaries);
  await replaceScopedSummaries(sql, "category_summaries", workspaceId, projectId, summaries.categorySummaries);

  await recomputeWorkspace(sql, workspaceId);
}

async function writeProjectMetrics(
  sql: Sql,
  workspaceId: string,
  projectId: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const [existing] = await sql<{ payload: unknown }[]>`
    SELECT payload FROM project_metrics WHERE project_id = ${projectId}`;
  if (existing && sameJson(existing.payload, payload)) {
    return;
  }
  const riskLevel = typeof payload.riskLevel === "string" ? payload.riskLevel : null;
  await sql`
    INSERT INTO project_metrics (project_id, workspace_id, risk_level, payload, source_version, computed_at)
    VALUES (${projectId}, ${workspaceId}, ${riskLevel}, ${sql.json(payload as never)}, 1, now())
    ON CONFLICT (project_id) DO UPDATE SET
      workspace_id = EXCLUDED.workspace_id,
      risk_level = EXCLUDED.risk_level,
      payload = EXCLUDED.payload,
      source_version = project_metrics.source_version + 1,
      computed_at = now()`;
}

type SummaryTable = "project_summaries" | "weekly_summaries" | "entity_summaries" | "category_summaries";

async function upsertSummary(
  sql: Sql,
  table: SummaryTable,
  id: string,
  workspaceId: string,
  projectId: string,
  payload: Record<string, unknown>,
): Promise<void> {
  if (!id) {
    return;
  }
  const json = toJson(payload);
  const [existing] = await sql<{ payload: unknown }[]>`
    SELECT payload FROM ${sql(table)} WHERE id = ${id}`;
  if (existing && sameJson(existing.payload, json)) {
    return;
  }
  await sql`
    INSERT INTO ${sql(table)} (id, workspace_id, project_id, payload, computed_at)
    VALUES (${id}, ${workspaceId}, ${projectId}, ${sql.json(json as never)}, now())
    ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, computed_at = now()`;
}

/** replaceScopedSummaryDocs: delete rows of this (workspace, project) not in the new set, upsert the rest. */
async function replaceScopedSummaries(
  sql: Sql,
  table: Exclude<SummaryTable, "project_summaries">,
  workspaceId: string,
  projectId: string,
  summaries: TriggerDocData[],
): Promise<void> {
  const nextIds = summaries.map((s) => `${s.id ?? ""}`).filter(Boolean);
  if (nextIds.length === 0) {
    await sql`DELETE FROM ${sql(table)} WHERE workspace_id = ${workspaceId} AND project_id = ${projectId}`;
  } else {
    await sql`
      DELETE FROM ${sql(table)}
      WHERE workspace_id = ${workspaceId} AND project_id = ${projectId} AND id NOT IN ${sql(nextIds)}`;
  }
  for (const summary of summaries) {
    const { id, ...payload } = summary;
    await upsertSummary(sql, table, `${id ?? ""}`, workspaceId, projectId, payload);
  }
}

export async function recomputeWorkspace(sql: Sql, workspaceId: string): Promise<void> {
  const rows = await sql<{ payload: Record<string, unknown> }[]>`
    SELECT payload FROM project_metrics
    WHERE workspace_id = ${workspaceId}
      AND COALESCE((payload ->> 'isArchived')::boolean, false) = false`;
  const payload = toJson(
    buildWorkspaceMetricsPayload(
      workspaceId,
      rows.map((r) => r.payload),
    ),
  );
  const [existing] = await sql<{ payload: unknown }[]>`
    SELECT payload FROM workspace_metrics WHERE workspace_id = ${workspaceId}`;
  if (existing && sameJson(existing.payload, payload)) {
    return;
  }
  await sql`
    INSERT INTO workspace_metrics (workspace_id, payload, source_version, computed_at)
    VALUES (${workspaceId}, ${sql.json(payload as never)}, 1, now())
    ON CONFLICT (workspace_id) DO UPDATE SET
      payload = EXCLUDED.payload,
      source_version = workspace_metrics.source_version + 1,
      computed_at = now()`;
}

/** recomputeWorkerAccountingSummary: summary id `${workspaceId}_${workerId}`; removed with its last record. */
export async function recomputeWorkerAccounting(
  sql: Sql,
  workspaceId: string,
  workerId: string,
): Promise<void> {
  const id = `${workspaceId}_${workerId}`;
  const records = await sql<Row[]>`
    SELECT * FROM worker_accounting_records
    WHERE workspace_id = ${workspaceId} AND worker_id = ${workerId}`;
  if (records.length === 0) {
    await sql`DELETE FROM worker_accounting_summaries WHERE id = ${id}`;
    return;
  }
  const payload = toJson(
    buildWorkerAccountingSummaryPayload({
      workspaceId,
      workerId,
      records: records.map(rowToDoc),
    }),
  );
  const [existing] = await sql<{ payload: unknown }[]>`
    SELECT payload FROM worker_accounting_summaries WHERE id = ${id}`;
  if (existing && sameJson(existing.payload, payload)) {
    return;
  }
  await sql`
    INSERT INTO worker_accounting_summaries (id, workspace_id, worker_id, payload, computed_at)
    VALUES (${id}, ${workspaceId}, ${workerId}, ${sql.json(payload as never)}, now())
    ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, computed_at = now()`;
}
