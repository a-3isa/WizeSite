import { assertCanMutateMoney } from "../auth/roles";
import type { Sql } from "../db/pool";
import { RpcError as HttpsError } from "../domain/errors";
import { parsePaymentStatus } from "../domain/money";
import { recomputeProject } from "../recompute/persist";
import { consumeMonthly, refundMonthly } from "./quota";
import { ensureAttachmentItems, existingMutation, hasContractValue, legacyFields, mutationIdOf, toDate } from "./records";
import type { RpcRegistry } from "./types";
import { asRecord, newDocId, requireNumber, requireString, text } from "./validation";

/**
 * Payment RPCs ported from functions/src/index.ts (createPaymentWithQuotaForUser,
 * updatePaymentForUser, archivePaymentWithQuotaRefundForUser), including the feature-003
 * invariant: payments need a project with a contract value.
 */

const NO_CONTRACT = "Set a contract value on this project before recording payments.";

type ProjectRow = { workspace_id: string; is_archived: boolean; contract_value: string | null };

async function projectOf(sql: Sql, projectId: string): Promise<ProjectRow | undefined> {
  const [project] = await sql<ProjectRow[]>`
    SELECT workspace_id, is_archived, contract_value FROM projects WHERE id = ${projectId}`;
  return project;
}

function positiveAmount(data: Record<string, unknown>): number {
  const amount = requireNumber(data, "amount");
  if (amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be greater than zero");
  }
  return amount;
}

export async function createPaymentWithQuotaForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<{ id: string; clientMutationId?: string }> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const projectId = requireString(data, "projectId");
  const amount = positiveAmount(data);
  const project = await projectOf(sql, projectId);
  if (!project || project.workspace_id !== workspaceId) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  if (project.is_archived) {
    throw new HttpsError("permission-denied", "Project is archived and can no longer accept payments.");
  }
  // Rejected before any quota is consumed, so a refused payment never costs the allowance.
  if (!hasContractValue(project.contract_value)) {
    throw new HttpsError("failed-precondition", NO_CONTRACT);
  }
  const clientMutationId = mutationIdOf(data);
  const replay = await existingMutation(sql, "payments", workspaceId, clientMutationId);
  if (replay) {
    return replay;
  }
  await consumeMonthly(sql, workspaceId, "paymentsPerMonth");

  const attachments = ensureAttachmentItems(data, "attachments");
  const id = newDocId();
  await sql`
    INSERT INTO payments (id, workspace_id, project_id, amount, paid_amount, date, description, notes,
                          payment_method, payment_status, entity_id, entity_type, entity_name, attachments,
                          is_archived, client_mutation_id, created_by, legacy)
    VALUES (${id}, ${workspaceId}, ${projectId}, ${amount},
            ${Number.isFinite(Number(data.paidAmount)) ? Number(data.paidAmount) : null},
            ${toDate(data.date) ?? new Date()}, ${`${data.description ?? data.notes ?? ""}`.trim()},
            ${text(data, "notes")}, ${text(data, "paymentMethod", "cash")},
            ${parsePaymentStatus(data.paymentStatus, "paid")}, ${text(data, "entityId") || null},
            ${text(data, "entityType", "other")}, ${text(data, "entityName")}, ${sql.json(attachments as never)},
            false, ${clientMutationId}, ${uid}, ${sql.json(legacyFields(data) as never)})`;
  await recomputeProject(sql, workspaceId, projectId);
  return { id, clientMutationId: clientMutationId ?? "" };
}

type PaymentRow = { workspace_id: string; project_id: string; is_archived: boolean; payment_status: string };

async function paymentInWorkspace(sql: Sql, paymentId: string, workspaceId: string): Promise<PaymentRow> {
  const [payment] = await sql<PaymentRow[]>`
    SELECT workspace_id, project_id, is_archived, payment_status FROM payments WHERE id = ${paymentId} FOR UPDATE`;
  if (!payment) {
    throw new HttpsError("not-found", "Payment not found");
  }
  if (payment.workspace_id !== workspaceId) {
    throw new HttpsError("permission-denied", "Payment is not available in this workspace");
  }
  return payment;
}

/**
 * Note for parity: like the Firestore version, `paidAmount` in the request only fed the cash
 * delta and is not stored, so the stored paid amount is unchanged by an edit.
 */
export async function updatePaymentForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const paymentId = requireString(data, "paymentId");
  const projectId = requireString(data, "projectId");
  const amount = positiveAmount(data);

  const payment = await paymentInWorkspace(sql, paymentId, workspaceId);
  if (payment.is_archived) {
    throw new HttpsError("failed-precondition", "Archived payments cannot be edited.");
  }
  const project = await projectOf(sql, projectId);
  if (!project) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  if (project.workspace_id !== workspaceId || project.is_archived) {
    throw new HttpsError("permission-denied", "Project is not available in this workspace");
  }
  // A payment can be moved to another project; it must not land on a contract-less one.
  if (!hasContractValue(project.contract_value)) {
    throw new HttpsError("failed-precondition", NO_CONTRACT);
  }
  const attachments = data.attachments != null ? ensureAttachmentItems(data, "attachments") : null;

  await sql`
    UPDATE payments SET
      project_id = ${projectId},
      amount = ${amount},
      date = ${toDate(data.date) ?? new Date()},
      payment_method = ${text(data, "paymentMethod", "cash")},
      payment_status = ${parsePaymentStatus(data.paymentStatus ?? payment.payment_status, "paid")},
      notes = ${text(data, "notes")},
      client_mutation_id = ${mutationIdOf(data)},
      attachments = COALESCE(${attachments === null ? null : sql.json(attachments as never)}, attachments),
      legacy = legacy || ${sql.json(legacyFields({ clientUpdatedAt: data.clientUpdatedAt }) as never)},
      updated_at = now()
    WHERE id = ${paymentId}`;
  await recomputeProject(sql, workspaceId, projectId);
  if (payment.project_id && payment.project_id !== projectId) {
    await recomputeProject(sql, workspaceId, payment.project_id);
  }
}

export async function archivePaymentWithQuotaRefundForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const paymentId = requireString(data, "paymentId");
  const payment = await paymentInWorkspace(sql, paymentId, workspaceId);
  if (payment.is_archived) {
    return;
  }
  await sql`UPDATE payments SET is_archived = true, archived_at = now(), updated_at = now() WHERE id = ${paymentId}`;
  await refundMonthly(sql, workspaceId, "paymentsPerMonth");
  if (payment.project_id) {
    await recomputeProject(sql, workspaceId, payment.project_id);
  }
}

export const paymentRpcs: RpcRegistry = {
  createPaymentWithQuota: {
    mutating: true,
    handler: (ctx, data) => createPaymentWithQuotaForUser(ctx.sql, ctx.uid, asRecord(data)),
  },
  updatePayment: {
    mutating: true,
    handler: async (ctx, data) => {
      await updatePaymentForUser(ctx.sql, ctx.uid, asRecord(data));
      return null;
    },
  },
  archivePaymentWithQuotaRefund: {
    mutating: true,
    handler: async (ctx, data) => {
      await archivePaymentWithQuotaRefundForUser(ctx.sql, ctx.uid, asRecord(data));
      return null;
    },
  },
};
