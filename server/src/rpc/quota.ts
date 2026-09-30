import type { Sql } from "../db/pool";
import { RpcError as HttpsError } from "../domain/errors";

/**
 * Plan limits and usage counters, ported from functions/src/index.ts (FREE_LIMITS, periodKey,
 * hasUnlimitedQuota, quotaError, the usage_counters docs). Counter rows keep the Firestore doc
 * ids: `${workspaceId}_${YYYYMM}` for monthly counts, `${workspaceId}_projects` for active projects.
 */
export type LimitType =
  | "activeProjects"
  | "expensesPerMonth"
  | "paymentsPerMonth"
  | "workerEntriesPerMonth"
  | "teamMembers";

export const FREE_LIMITS: Record<LimitType, number> = {
  activeProjects: 1,
  expensesPerMonth: 30,
  paymentsPerMonth: 10,
  workerEntriesPerMonth: 10,
  teamMembers: 1,
};

const USAGE_LIMITS_DISABLED = false;

export function periodKey(now = new Date()): string {
  const month = `${now.getUTCMonth() + 1}`.padStart(2, "0");
  return `${now.getUTCFullYear()}${month}`;
}

export function limitForType(type: LimitType): number {
  return FREE_LIMITS[type];
}

export function quotaError(type: LimitType, current: number, max: number): never {
  throw new HttpsError("failed-precondition", "LIMIT_REACHED", {
    code: "LIMIT_REACHED",
    limitType: type,
    current,
    max,
  });
}

/** A missing subscription is free/expired, as in subscriptionFromSnap. */
export async function hasUnlimitedQuota(sql: Sql, workspaceId: string): Promise<boolean> {
  if (USAGE_LIMITS_DISABLED) {
    return true;
  }
  const [sub] = await sql<{ tier: string; status: string }[]>`
    SELECT tier, status FROM subscriptions WHERE workspace_id = ${workspaceId}`;
  return sub?.tier === "pro" && ["active", "trial", "grace"].includes(sub.status);
}

type CounterColumn = "expenses_count" | "payments_count" | "worker_entries_count" | "active_projects";

/**
 * Locks the counter row for this transaction, creating it when missing. `seed` supplies the
 * starting value for a row that did not exist (activeProjects counts the live projects).
 */
async function lockCounter(
  sql: Sql,
  workspaceId: string,
  period: string,
  column: CounterColumn,
  seed: () => Promise<number>,
): Promise<number> {
  const id = `${workspaceId}_${period}`;
  const existing = await sql<Record<string, number>[]>`
    SELECT ${sql(column)} AS value FROM usage_counters WHERE id = ${id} FOR UPDATE`;
  if (existing.length > 0) {
    return Number(existing[0].value ?? 0);
  }
  const start = await seed();
  await sql`
    INSERT INTO usage_counters (id, workspace_id, period, ${sql(column)})
    VALUES (${id}, ${workspaceId}, ${period}, ${start})
    ON CONFLICT (id) DO NOTHING`;
  const [row] = await sql<Record<string, number>[]>`
    SELECT ${sql(column)} AS value FROM usage_counters WHERE id = ${id} FOR UPDATE`;
  return Number(row.value ?? 0);
}

async function setCounter(
  sql: Sql,
  workspaceId: string,
  period: string,
  column: CounterColumn,
  value: number,
): Promise<void> {
  await sql`
    UPDATE usage_counters SET ${sql(column)} = ${Math.max(0, value)}, updated_at = now()
    WHERE id = ${`${workspaceId}_${period}`}`;
}

const MONTHLY: Record<"expensesPerMonth" | "paymentsPerMonth" | "workerEntriesPerMonth", CounterColumn> = {
  expensesPerMonth: "expenses_count",
  paymentsPerMonth: "payments_count",
  workerEntriesPerMonth: "worker_entries_count",
};

export type MonthlyLimit = keyof typeof MONTHLY;

/** commitIdempotentCreate's quota guard + increment for a monthly count. */
export async function consumeMonthly(sql: Sql, workspaceId: string, type: MonthlyLimit): Promise<void> {
  const enforce = !(await hasUnlimitedQuota(sql, workspaceId));
  const period = periodKey();
  const current = await lockCounter(sql, workspaceId, period, MONTHLY[type], async () => 0);
  const max = limitForType(type);
  if (enforce && current + 1 > max) {
    // Same arguments as today's onExceeded: (type, max, max).
    quotaError(type, max, max);
  }
  await setCounter(sql, workspaceId, period, MONTHLY[type], current + 1);
}

/** Archive refund: never below zero (archive*WithQuotaRefund). */
export async function refundMonthly(sql: Sql, workspaceId: string, type: MonthlyLimit): Promise<void> {
  await refundMonthlyBy(sql, workspaceId, type, 1);
}

export async function refundMonthlyBy(sql: Sql, workspaceId: string, type: MonthlyLimit, count: number): Promise<void> {
  const period = periodKey();
  const current = await lockCounter(sql, workspaceId, period, MONTHLY[type], async () => 0);
  await setCounter(sql, workspaceId, period, MONTHLY[type], current - count);
}

/** isCountedActiveProject: status active (blank = active) and not archived. */
async function countActiveProjects(sql: Sql, workspaceId: string): Promise<number> {
  const [{ count }] = await sql<{ count: number }[]>`
    SELECT count(*)::int AS count FROM projects
    WHERE workspace_id = ${workspaceId} AND COALESCE(NULLIF(trim(status), ''), 'active') = 'active'
      AND NOT is_archived`;
  return count;
}

/**
 * Active-project count: `delta` +1 on create/unarchive (checked against the plan when `enforce`),
 * -1 on archive. Returns the value before the change.
 */
export async function changeActiveProjects(
  sql: Sql,
  workspaceId: string,
  delta: 1 | -1,
  options: { enforce: boolean; currentForError?: "max" | "current" },
): Promise<void> {
  const current = await lockCounter(sql, workspaceId, "projects", "active_projects", () =>
    countActiveProjects(sql, workspaceId),
  );
  const max = limitForType("activeProjects");
  if (delta > 0 && options.enforce && current + 1 > max) {
    // createProjectWithQuota reports (max, max); unarchiveProject reports (current, max).
    quotaError("activeProjects", options.currentForError === "current" ? current : max, max);
  }
  await setCounter(sql, workspaceId, "projects", "active_projects", current + delta);
}
