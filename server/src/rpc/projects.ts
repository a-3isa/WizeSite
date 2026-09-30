import { rm } from "node:fs/promises";
import path from "node:path";

import { assertCanManageProject, assertMember } from "../auth/roles";
import type { Sql } from "../db/pool";
import { RpcError as HttpsError } from "../domain/errors";
import { canCreateProject, canDeleteProjectCascade } from "../domain/money";
import { isAllowedAttachmentStoragePath } from "../domain/storage_lifecycle";
import { recomputeProject, recomputeWorkspace } from "../recompute/persist";
import { changeActiveProjects, hasUnlimitedQuota, refundMonthlyBy } from "./quota";
import { existingMutation, hasContractValue, legacyFields, mutationIdOf, toDate } from "./records";
import type { RpcRegistry } from "./types";
import { asRecord, newDocId, optionalPositiveNumber, requireString, text } from "./validation";

/**
 * Project RPCs ported from functions/src/index.ts (createProjectWithQuotaForUser,
 * updateProjectForUser, archiveProjectForUser, unarchiveProjectForUser). `sql` is the request's
 * transaction; derived state is recomputed before it commits (research R6).
 */

type ProjectRow = { id: string; workspace_id: string; is_archived: boolean; status: string; contract_value: string | null };

async function projectInWorkspace(sql: Sql, projectId: string, workspaceId: string): Promise<ProjectRow> {
  const [project] = await sql<ProjectRow[]>`
    SELECT id, workspace_id, is_archived, status, contract_value FROM projects WHERE id = ${projectId} FOR UPDATE`;
  if (!project) {
    throw new HttpsError("not-found", "Project not found");
  }
  if (project.workspace_id !== workspaceId) {
    throw new HttpsError("permission-denied", "Project is not available in this workspace");
  }
  return project;
}

export async function createProjectWithQuotaForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<{ id: string; clientMutationId?: string }> {
  const workspaceId = requireString(data, "workspaceId");
  const role = await assertMember(sql, workspaceId, uid);
  if (!canCreateProject(role)) {
    throw new HttpsError("permission-denied", "Not allowed to create project");
  }
  const name = requireString(data, "name");
  const contractValue = optionalPositiveNumber(data, "contractValue");
  const budgetLimit = optionalPositiveNumber(data, "budgetLimit");
  const clientMutationId = mutationIdOf(data);

  const replay = await existingMutation(sql, "projects", workspaceId, clientMutationId);
  if (replay) {
    return replay;
  }
  await changeActiveProjects(sql, workspaceId, 1, { enforce: !(await hasUnlimitedQuota(sql, workspaceId)) });

  const id = newDocId();
  await sql`
    INSERT INTO projects (id, workspace_id, name, client_name, description, location, status, contract_value,
                          budget_limit, start_date, expected_end_date, completion_percentage, is_archived,
                          client_mutation_id, created_by, legacy)
    VALUES (${id}, ${workspaceId}, ${name}, ${text(data, "clientName")}, ${text(data, "description")},
            ${text(data, "location")}, 'active', ${contractValue}, ${budgetLimit},
            ${toDate(data.startDate) ?? new Date()}, ${toDate(data.expectedEndDate)},
            ${Number(data.completionPercentage ?? 0)}, false, ${clientMutationId}, ${uid},
            ${sql.json(legacyFields(data, { ownerId: uid }) as never)})`;
  await recomputeProject(sql, workspaceId, id);
  return { id, clientMutationId: clientMutationId ?? "" };
}

export async function updateProjectForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanManageProject(sql, workspaceId, uid);
  const projectId = requireString(data, "projectId");
  const project = await projectInWorkspace(sql, projectId, workspaceId);
  if (project.is_archived) {
    throw new HttpsError("failed-precondition", "Archived projects cannot be edited.");
  }
  const contractValue = optionalPositiveNumber(data, "contractValue");

  // Core invariant: a project with no Contract Value cannot hold payments. Archived payments do
  // not block (archiving is the only removal the app offers).
  if (hasContractValue(project.contract_value) && contractValue === null) {
    const [live] = await sql`
      SELECT 1 FROM payments WHERE project_id = ${projectId} AND NOT is_archived LIMIT 1`;
    if (live) {
      throw new HttpsError("failed-precondition", "Remove this project's payments before clearing its contract value.");
    }
  }

  await sql`
    UPDATE projects SET
      name = ${requireString(data, "name")},
      client_name = ${text(data, "clientName")},
      contract_value = ${contractValue},
      start_date = ${toDate(data.startDate) ?? new Date()},
      expected_end_date = ${toDate(data.expectedEndDate)},
      location = ${text(data, "location")},
      description = ${text(data, "description")},
      budget_limit = ${optionalPositiveNumber(data, "budgetLimit")},
      completion_percentage = ${Number(data.completionPercentage ?? 0)},
      status = ${text(data, "status", "active") || "active"},
      client_mutation_id = ${mutationIdOf(data)},
      legacy = legacy || ${sql.json(legacyFields({ clientUpdatedAt: data.clientUpdatedAt }) as never)},
      updated_at = now()
    WHERE id = ${projectId}`;
  await recomputeProject(sql, workspaceId, projectId);
}

function countsAsActive(status: string | null): boolean {
  return (`${status ?? "active"}`.trim() || "active") === "active";
}

export async function archiveProjectForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanManageProject(sql, workspaceId, uid);
  const projectId = requireString(data, "projectId");
  const project = await projectInWorkspace(sql, projectId, workspaceId);
  if (project.is_archived) {
    return;
  }
  if (countsAsActive(project.status)) {
    await changeActiveProjects(sql, workspaceId, -1, { enforce: false });
  }
  await sql`
    UPDATE projects SET is_archived = true, archived_at = now(), client_mutation_id = ${mutationIdOf(data)},
      legacy = legacy || ${sql.json(legacyFields({ clientUpdatedAt: data.clientUpdatedAt }) as never)},
      updated_at = now()
    WHERE id = ${projectId}`;
  await recomputeProject(sql, workspaceId, projectId);
}

export async function unarchiveProjectForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanManageProject(sql, workspaceId, uid);
  const projectId = requireString(data, "projectId");
  const enforce = !(await hasUnlimitedQuota(sql, workspaceId));
  const project = await projectInWorkspace(sql, projectId, workspaceId);
  if (!project.is_archived) {
    return;
  }
  if (countsAsActive(project.status)) {
    await changeActiveProjects(sql, workspaceId, 1, { enforce, currentForError: "current" });
  }
  await sql`
    UPDATE projects SET is_archived = false, archived_at = NULL, client_mutation_id = ${mutationIdOf(data)},
      legacy = legacy || ${sql.json(legacyFields({ clientUpdatedAt: data.clientUpdatedAt }) as never)},
      updated_at = now()
    WHERE id = ${projectId}`;
  await recomputeProject(sql, workspaceId, projectId);
}

/** Accounting records Firebase's cascade left in place; they only point at the project. */
const DETACHED_ON_DELETE = [
  "worker_accounting_records",
  "contractor_accounting_records",
  "equipment_accounting_records",
  "transport_provider_accounting_records",
] as const;

/**
 * Port of deleteProjectCascade. Deletes the project with its expenses, payments, worker entries,
 * metrics and notifications; refunds this month's counts for live records and the active-project
 * count; then deletes the attachment files (best effort, as the Storage cleanup was).
 * Accounting records are kept, as in Firebase: the FK would cascade them, so they are detached
 * first with the old projectId kept in `legacy` (the app reads the same projectId as before).
 */
export async function deleteProjectCascadeForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
  files: { root: string },
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  const role = await assertMember(sql, workspaceId, uid);
  if (!canDeleteProjectCascade(role)) {
    throw new HttpsError("permission-denied", "Not allowed to delete project");
  }
  const projectId = requireString(data, "projectId");
  const project = await projectInWorkspace(sql, projectId, workspaceId);

  const liveCount = async (table: "expenses" | "payments" | "worker_entries") => {
    const [{ count }] = await sql<{ count: number }[]>`
      SELECT count(*)::int AS count FROM ${sql(table)}
      WHERE workspace_id = ${workspaceId} AND project_id = ${projectId} AND NOT is_archived`;
    return count;
  };
  const refunds = {
    expensesPerMonth: await liveCount("expenses"),
    paymentsPerMonth: await liveCount("payments"),
    workerEntriesPerMonth: await liveCount("worker_entries"),
  } as const;
  const attachmentRows = await sql<{ attachments: unknown }[]>`
    SELECT attachments FROM expenses WHERE workspace_id = ${workspaceId} AND project_id = ${projectId}
    UNION ALL SELECT attachments FROM payments WHERE workspace_id = ${workspaceId} AND project_id = ${projectId}
    UNION ALL SELECT attachments FROM worker_entries WHERE workspace_id = ${workspaceId} AND project_id = ${projectId}`;
  const storagePaths = attachmentRows.flatMap((row) =>
    (Array.isArray(row.attachments) ? row.attachments : [])
      .map((item) => `${(item as Record<string, unknown> | null)?.storagePath ?? ""}`.trim())
      .filter(Boolean),
  );

  for (const table of DETACHED_ON_DELETE) {
    await sql`
      UPDATE ${sql(table)} SET legacy = legacy || jsonb_build_object('projectId', project_id), project_id = NULL,
        updated_at = now()
      WHERE workspace_id = ${workspaceId} AND project_id = ${projectId}`;
  }
  await sql`DELETE FROM notifications WHERE workspace_id = ${workspaceId} AND legacy->>'projectId' = ${projectId}`;
  // Expenses, payments, worker entries and every derived row go with the project (FK cascade).
  await sql`DELETE FROM projects WHERE id = ${projectId}`;

  for (const [type, count] of Object.entries(refunds) as Array<[keyof typeof refunds, number]>) {
    if (count > 0) {
      await refundMonthlyBy(sql, workspaceId, type, count);
    }
  }
  if (countsAsActive(project.status) && !project.is_archived) {
    await changeActiveProjects(sql, workspaceId, -1, { enforce: false });
  }
  await recomputeWorkspace(sql, workspaceId);

  const root = path.resolve(files.root);
  await Promise.all(
    storagePaths.map(async (storagePath) => {
      const target = path.resolve(root, storagePath);
      if (!isAllowedAttachmentStoragePath(storagePath) || !target.startsWith(root + path.sep)) {
        return;
      }
      try {
        await rm(target, { force: true });
      } catch {
        // Best-effort file cleanup, as with the Storage cleanup before.
      }
    }),
  );
}

export const projectRpcs = (files: { root: string }): RpcRegistry => ({
  createProjectWithQuota: {
    mutating: true,
    handler: (ctx, data) => createProjectWithQuotaForUser(ctx.sql, ctx.uid, asRecord(data)),
  },
  updateProject: {
    mutating: true,
    handler: async (ctx, data) => {
      await updateProjectForUser(ctx.sql, ctx.uid, asRecord(data));
      return null;
    },
  },
  archiveProject: {
    mutating: true,
    handler: async (ctx, data) => {
      await archiveProjectForUser(ctx.sql, ctx.uid, asRecord(data));
      return null;
    },
  },
  unarchiveProject: {
    mutating: true,
    handler: async (ctx, data) => {
      await unarchiveProjectForUser(ctx.sql, ctx.uid, asRecord(data));
      return null;
    },
  },
  deleteProjectCascade: {
    mutating: true,
    handler: async (ctx, data) => {
      await deleteProjectCascadeForUser(ctx.sql, ctx.uid, asRecord(data), files);
      return null;
    },
  },
});
