import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

import { createPool, type Sql } from "../db/pool";
import { withTransaction } from "../db/tx";
import { recomputeProject, recomputeWorkerAccounting } from "./persist";

/**
 * Nightly reconciler (tasks.md T078): recomputes every project's derived state and every worker
 * accounting summary, and reports money drift, i.e. stored totals that differ from what the records
 * add up to. Every write already recomputes in its transaction, so drift means a bug or a write
 * made outside the API. Other derived fields depend on the date (weekly windows) and change daily
 * by design, so only the money totals count as drift.
 *
 *   npm run reconcile                  # once; exit 1 on drift
 *   node dist/src/recompute/reconcile.js --daily   # stay up and run at 02:00 UTC every day
 */
const TOTALS = ["totalExpenses", "totalPayments", "netProfit"] as const;
const HALF_CENT = 0.005;

export interface Drift {
  workspaceId: string;
  projectId: string;
  field: (typeof TOTALS)[number];
  stored: number;
  recomputed: number;
}

export interface ReconcileResult {
  projects: number;
  workerSummaries: number;
  drift: Drift[];
}

async function storedTotals(sql: Sql, projectId: string): Promise<Record<string, number>> {
  const [row] = await sql<{ payload: Record<string, unknown> }[]>`
    SELECT payload FROM project_metrics WHERE project_id = ${projectId}`;
  return Object.fromEntries(TOTALS.map((key) => [key, Number(row?.payload?.[key] ?? 0)]));
}

export async function reconcile(sql: Sql, now: Date = new Date()): Promise<ReconcileResult> {
  const projects = await sql<{ id: string; workspace_id: string }[]>`
    SELECT id, workspace_id FROM projects ORDER BY workspace_id, id`;
  const drift: Drift[] = [];
  for (const project of projects) {
    // One short transaction per project: the app keeps writing while this runs.
    await withTransaction(sql, async (tx) => {
      await tx`SELECT id FROM projects WHERE id = ${project.id} FOR UPDATE`;
      const before = await storedTotals(tx, project.id);
      await recomputeProject(tx, project.workspace_id, project.id, now);
      const after = await storedTotals(tx, project.id);
      for (const field of TOTALS) {
        if (Math.abs(before[field] - after[field]) >= HALF_CENT) {
          drift.push({ workspaceId: project.workspace_id, projectId: project.id, field, stored: before[field], recomputed: after[field] });
        }
      }
    });
  }
  const workers = await sql<{ workspace_id: string; worker_id: string }[]>`
    SELECT DISTINCT workspace_id, worker_id FROM worker_accounting_records WHERE worker_id IS NOT NULL`;
  for (const worker of workers) {
    await withTransaction(sql, (tx) => recomputeWorkerAccounting(tx, worker.workspace_id, worker.worker_id));
  }
  return { projects: projects.length, workerSummaries: workers.length, drift };
}

/** Runs once and writes the result to `stateFile`; returns true when there was no drift. */
export async function runAndRecord(sql: Sql, stateFile: string): Promise<boolean> {
  const startedAt = new Date();
  const result = await reconcile(sql, startedAt);
  // Rollback tombstones (migration 006) are only needed for the window after cutover.
  await sql`DELETE FROM deleted_rows WHERE deleted_at < now() - interval '30 days'`;
  const record ={ ...result, startedAt: startedAt.toISOString(), finishedAt: new Date().toISOString() };
  await mkdir(path.dirname(stateFile), { recursive: true });
  await writeFile(stateFile, `${JSON.stringify(record, null, 2)}\n`, "utf8");
  for (const d of result.drift) {
    console.error(`drift ${d.workspaceId}/${d.projectId} ${d.field}: stored ${d.stored}, records ${d.recomputed}`);
  }
  console.log(`reconciled ${result.projects} project(s), ${result.workerSummaries} worker summary(ies), ${result.drift.length} drift(s)`);
  return result.drift.length === 0;
}

/** Milliseconds from `now` until the next `hourUtc`:00 UTC (a full day when it is that time now). */
export function msUntilNextRun(now: Date, hourUtc: number): number {
  const next = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), hourUtc));
  if (next.getTime() <= now.getTime()) {
    next.setUTCDate(next.getUTCDate() + 1);
  }
  return next.getTime() - now.getTime();
}

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required");
  }
  const stateFile = process.env.RECONCILE_STATE ?? "/srv/wizesite/state/reconcile/reconcile.json";
  const sql = createPool(databaseUrl, { max: 2 });
  if (!process.argv.includes("--daily")) {
    const ok = await runAndRecord(sql, stateFile);
    await sql.end({ timeout: 5 });
    process.exitCode = ok ? 0 : 1;
    return;
  }
  const hour = Number(process.env.RECONCILE_HOUR_UTC ?? 2);
  for (;;) {
    await new Promise((resolve) => setTimeout(resolve, msUntilNextRun(new Date(), hour)));
    try {
      await runAndRecord(sql, stateFile);
    } catch (error) {
      console.error("reconcile failed", error);
    }
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
