import { assertCanMutateMoney, assertMember } from "../auth/roles";
import type { Sql } from "../db/pool";
import { normalizeWorkerStatus } from "../domain/accounting";
import { RpcError as HttpsError } from "../domain/errors";
import { recomputeProject } from "../recompute/persist";
import { consumeMonthly, refundMonthly } from "./quota";
import { ensureAttachmentItems, existingMutation, legacyFields, mutationIdOf, toDate } from "./records";
import type { RpcRegistry } from "./types";
import { asRecord, newDocId, requireMoney, requireString, text } from "./validation";

/**
 * Worker and worker-entry RPCs ported from functions/src/index.ts (createWorker, updateWorker,
 * archiveWorker, createWorkerEntryWithQuotaForUser, updateWorkerEntry,
 * archiveWorkerEntryWithQuotaRefundForUser).
 */

function billingTypeOf(data: Record<string, unknown>): "daily" | "project" {
  return text(data, "billingType", "daily").toLowerCase() === "project" ? "project" : "daily";
}

function wageFor(data: Record<string, unknown>, billingType: "daily" | "project"): number {
  const dailyWage = requireMoney(data, "dailyWage");
  if (billingType === "daily" && dailyWage <= 0) {
    throw new HttpsError("invalid-argument", "Daily workers must have daily wage greater than zero");
  }
  return billingType === "daily" ? dailyWage : 0;
}

export async function createWorkerForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<{ id: string; clientMutationId?: string }> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(sql, workspaceId, uid);
  const name = requireString(data, "name");
  const billingType = billingTypeOf(data);
  const status = normalizeWorkerStatus(data.status);
  const dailyWage = wageFor(data, billingType);
  const clientMutationId = mutationIdOf(data);

  const replay = await existingMutation(sql, "workers", workspaceId, clientMutationId);
  if (replay) {
    return replay;
  }
  const id = newDocId();
  await sql`
    INSERT INTO workers (id, workspace_id, name, phone_number, worker_type, billing_type, daily_wage, status, notes,
                         is_archived, client_mutation_id, created_by, legacy)
    VALUES (${id}, ${workspaceId}, ${name}, ${text(data, "phoneNumber")}, ${text(data, "workerType")},
            ${billingType}, ${dailyWage}, ${status}, ${text(data, "notes")}, false, ${clientMutationId}, ${uid},
            ${sql.json(legacyFields(data) as never)})`;
  return { id, clientMutationId: clientMutationId ?? "" };
}

type WorkerRow = { workspace_id: string; is_archived: boolean; status: string };

async function workerInWorkspace(sql: Sql, workerId: string, workspaceId: string): Promise<WorkerRow> {
  const [worker] = await sql<WorkerRow[]>`
    SELECT workspace_id, is_archived, status FROM workers WHERE id = ${workerId} FOR UPDATE`;
  if (!worker) {
    throw new HttpsError("not-found", "Worker not found");
  }
  if (worker.workspace_id !== workspaceId) {
    throw new HttpsError("permission-denied", "Worker is not available in this workspace");
  }
  return worker;
}

export async function updateWorkerForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(sql, workspaceId, uid);
  const workerId = requireString(data, "workerId");
  const name = requireString(data, "name");
  const billingType = billingTypeOf(data);
  const dailyWage = wageFor(data, billingType);
  const worker = await workerInWorkspace(sql, workerId, workspaceId);
  if (worker.is_archived) {
    throw new HttpsError("failed-precondition", "Archived workers cannot be edited.");
  }
  const status = normalizeWorkerStatus(data.status ?? worker.status ?? "active");
  await sql`
    UPDATE workers SET
      name = ${name},
      phone_number = ${text(data, "phoneNumber")},
      daily_wage = ${dailyWage},
      billing_type = ${billingType},
      worker_type = ${text(data, "workerType")},
      notes = ${text(data, "notes")},
      status = ${status},
      client_mutation_id = ${mutationIdOf(data)},
      legacy = legacy || ${sql.json(legacyFields({ clientUpdatedAt: data.clientUpdatedAt }) as never)},
      updated_at = now()
    WHERE id = ${workerId}`;
}

/** Firestore set isArchived again on an archived worker too; the result is the same. */
export async function archiveWorkerForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(sql, workspaceId, uid);
  const workerId = requireString(data, "workerId");
  await workerInWorkspace(sql, workerId, workspaceId);
  await sql`
    UPDATE workers SET is_archived = true, client_mutation_id = ${mutationIdOf(data)},
      legacy = legacy || ${sql.json(legacyFields({ clientUpdatedAt: data.clientUpdatedAt }) as never)},
      updated_at = now()
    WHERE id = ${workerId}`;
}

function daysAndWage(data: Record<string, unknown>): { daysWorked: number; dailyWage: number } {
  const daysWorked = requireMoney(data, "daysWorked");
  const dailyWage = requireMoney(data, "dailyWage");
  if (daysWorked <= 0 || dailyWage <= 0) {
    throw new HttpsError("invalid-argument", "Days worked and daily wage must be > 0");
  }
  return { daysWorked, dailyWage };
}

/** days × wage, both with at most 2 decimals, is exact at 4 (float noise dropped). */
function totalCostOf(daysWorked: number, dailyWage: number): number {
  return Math.round(daysWorked * dailyWage * 10_000) / 10_000;
}

type ProjectRow = { workspace_id: string; is_archived: boolean };

async function entryProject(sql: Sql, projectId: string, workspaceId: string): Promise<void> {
  const [project] = await sql<ProjectRow[]>`SELECT workspace_id, is_archived FROM projects WHERE id = ${projectId}`;
  if (!project || project.workspace_id !== workspaceId) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  if (project.is_archived) {
    throw new HttpsError("permission-denied", "Project is archived and can no longer accept worker entries.");
  }
}

export async function createWorkerEntryWithQuotaForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<{ id: string; clientMutationId?: string }> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const workerId = requireString(data, "workerId");
  const projectId = requireString(data, "projectId");
  const { daysWorked, dailyWage } = daysAndWage(data);

  const [worker] = await sql<{ workspace_id: string; is_archived: boolean }[]>`
    SELECT workspace_id, is_archived FROM workers WHERE id = ${workerId}`;
  if (!worker || worker.workspace_id !== workspaceId) {
    throw new HttpsError("invalid-argument", "Worker does not exist");
  }
  if (worker.is_archived) {
    throw new HttpsError("permission-denied", "Worker is archived and can no longer accept new entries.");
  }
  await entryProject(sql, projectId, workspaceId);

  const clientMutationId = mutationIdOf(data);
  const replay = await existingMutation(sql, "worker_entries", workspaceId, clientMutationId);
  if (replay) {
    return replay;
  }
  const attachments = ensureAttachmentItems(data, "attachments");
  await consumeMonthly(sql, workspaceId, "workerEntriesPerMonth");

  const id = newDocId();
  await sql`
    INSERT INTO worker_entries (id, workspace_id, project_id, worker_id, date, days_worked, daily_wage, total_cost,
                                notes, attachments, is_archived, client_mutation_id, created_by, legacy)
    VALUES (${id}, ${workspaceId}, ${projectId}, ${workerId}, ${toDate(data.date) ?? new Date()}, ${daysWorked},
            ${dailyWage}, ${totalCostOf(daysWorked, dailyWage)}, ${text(data, "notes")},
            ${sql.json(attachments as never)}, false, ${clientMutationId}, ${uid},
            ${sql.json(legacyFields(data) as never)})`;
  await recomputeProject(sql, workspaceId, projectId);
  return { id, clientMutationId: clientMutationId ?? "" };
}

type EntryRow = { workspace_id: string; project_id: string; is_archived: boolean };

async function entryInWorkspace(sql: Sql, entryId: string, workspaceId: string): Promise<EntryRow> {
  const [entry] = await sql<EntryRow[]>`
    SELECT workspace_id, project_id, is_archived FROM worker_entries WHERE id = ${entryId} FOR UPDATE`;
  if (!entry) {
    throw new HttpsError("not-found", "Worker entry not found");
  }
  if (entry.workspace_id !== workspaceId) {
    throw new HttpsError("permission-denied", "Worker entry is not available in this workspace");
  }
  return entry;
}

export async function updateWorkerEntryForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const entryId = requireString(data, "entryId");
  const projectId = requireString(data, "projectId");
  const { daysWorked, dailyWage } = daysAndWage(data);
  const entry = await entryInWorkspace(sql, entryId, workspaceId);
  if (entry.is_archived) {
    throw new HttpsError("failed-precondition", "Archived worker entries cannot be edited.");
  }
  await entryProject(sql, projectId, workspaceId);
  const attachments = data.attachments != null ? ensureAttachmentItems(data, "attachments") : null;

  await sql`
    UPDATE worker_entries SET
      project_id = ${projectId},
      days_worked = ${daysWorked},
      daily_wage = ${dailyWage},
      total_cost = ${totalCostOf(daysWorked, dailyWage)},
      date = ${toDate(data.date) ?? new Date()},
      notes = ${text(data, "notes")},
      client_mutation_id = ${mutationIdOf(data)},
      attachments = COALESCE(${attachments === null ? null : sql.json(attachments as never)}, attachments),
      legacy = legacy || ${sql.json(legacyFields({ clientUpdatedAt: data.clientUpdatedAt }) as never)},
      updated_at = now()
    WHERE id = ${entryId}`;
  await recomputeProject(sql, workspaceId, projectId);
  if (entry.project_id && entry.project_id !== projectId) {
    await recomputeProject(sql, workspaceId, entry.project_id);
  }
}

export async function archiveWorkerEntryWithQuotaRefundForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const entryId = requireString(data, "entryId");
  const entry = await entryInWorkspace(sql, entryId, workspaceId);
  if (entry.is_archived) {
    return;
  }
  await sql`UPDATE worker_entries SET is_archived = true, archived_at = now(), updated_at = now() WHERE id = ${entryId}`;
  await refundMonthly(sql, workspaceId, "workerEntriesPerMonth");
  if (entry.project_id) {
    await recomputeProject(sql, workspaceId, entry.project_id);
  }
}

const done = (fn: (sql: Sql, uid: string, data: Record<string, unknown>) => Promise<void>) => ({
  mutating: true,
  handler: async (ctx: { sql: Sql; uid: string }, data: unknown) => {
    await fn(ctx.sql, ctx.uid, asRecord(data));
    return null;
  },
});

export const workerRpcs: RpcRegistry = {
  createWorker: {
    mutating: true,
    handler: (ctx, data) => createWorkerForUser(ctx.sql, ctx.uid, asRecord(data)),
  },
  updateWorker: done(updateWorkerForUser),
  archiveWorker: done(archiveWorkerForUser),
  createWorkerEntryWithQuota: {
    mutating: true,
    handler: (ctx, data) => createWorkerEntryWithQuotaForUser(ctx.sql, ctx.uid, asRecord(data)),
  },
  updateWorkerEntry: done(updateWorkerEntryForUser),
  archiveWorkerEntryWithQuotaRefund: done(archiveWorkerEntryWithQuotaRefundForUser),
};
