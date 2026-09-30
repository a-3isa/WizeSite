import { assertCanAccessAccounting } from "../auth/roles";
import type { Sql } from "../db/pool";
import { RpcError } from "../domain/errors";
import { recomputeWorkerAccounting } from "../recompute/persist";
import { ensureAttachmentItems, toDate } from "./records";
import type { RpcRegistry } from "./types";
import { asRecord, assertTwoDecimals, newDocId, requireString } from "./validation";

/**
 * Accounting-record writes the app made directly against Firestore (the domain save adapter and
 * worker_accounting_repository.dart). Validation mirrors firestore.rules validAccountingRecord /
 * validWorkerAccountingRecord / validDomainAccountingRecord, with one fix: equipment records carry
 * providerId/providerName (what the app sends and the schema stores), where the rules demanded
 * equipmentId/equipmentName and so refused every equipment save.
 */
const KINDS = {
  worker: { table: "worker_accounting_records", idField: "workerId", nameField: "workerName", idColumn: "worker_id", nameColumn: "worker_name" },
  contractor: { table: "contractor_accounting_records", idField: "contractorId", nameField: "contractorName", idColumn: "contractor_id", nameColumn: "contractor_name" },
  equipment: { table: "equipment_accounting_records", idField: "providerId", nameField: "providerName", idColumn: "provider_id", nameColumn: "provider_name" },
  transport: { table: "transport_provider_accounting_records", idField: "providerId", nameField: "providerName", idColumn: "provider_id", nameColumn: "provider_name" },
} as const;

export type AccountingKind = keyof typeof KINDS;

const PAYMENT_STATUSES = ["paid", "unpaid", "partial", "refunded", "cancelled"];
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

function invalid(message: string): never {
  throw new RpcError("invalid-argument", message);
}

function requireText(data: Record<string, unknown>, key: string): string {
  const value = data[key];
  if (typeof value !== "string") {
    invalid(`Missing required field: ${key}`);
  }
  return value.trim();
}

export async function upsertAccountingRecordForUser(
  sql: Sql,
  uid: string,
  kind: AccountingKind,
  data: Record<string, unknown>,
): Promise<{ id: string }> {
  const spec = KINDS[kind];
  const workspaceId = requireString(data, "workspaceId");
  await assertCanAccessAccounting(sql, workspaceId, uid);
  const projectId = requireString(data, "projectId");
  const ownerId = requireString(data, spec.idField);
  const ownerName = requireText(data, spec.nameField);
  const description = requireText(data, "description");
  const notes = requireText(data, "notes");
  const paymentMethod = requireText(data, "paymentMethod");
  const amount = Number(data.amount);
  if (typeof data.amount !== "number" || !Number.isFinite(amount) || amount <= 0) {
    invalid("Amount must be greater than zero");
  }
  assertTwoDecimals(amount, "amount");
  const date = toDate(data.date);
  if (!date) {
    invalid("Missing required field: date");
  }
  const paymentStatus = `${data.paymentStatus ?? ""}`;
  if (!PAYMENT_STATUSES.includes(paymentStatus)) {
    invalid("Unsupported payment status");
  }
  let paidAmount: number | null = null;
  if (data.paidAmount != null && `${data.paidAmount}`.trim() !== "") {
    paidAmount = assertTwoDecimals(Number(data.paidAmount), "paidAmount");
  }
  if (kind === "worker" && paymentStatus === "partial") {
    if (paidAmount === null || !(paidAmount > 0 && paidAmount < amount)) {
      invalid("A partial payment needs a paid amount between zero and the total");
    }
  }
  const [project] = await sql<{ workspace_id: string }[]>`SELECT workspace_id FROM projects WHERE id = ${projectId}`;
  if (!project || project.workspace_id !== workspaceId) {
    invalid("Project does not exist");
  }
  const attachments = data.attachments != null ? ensureAttachmentItems(data, "attachments") : null;

  const requestedId = `${data.id ?? ""}`.trim();
  if (requestedId && !ID_PATTERN.test(requestedId)) {
    invalid("Invalid record id");
  }
  const [existing] = requestedId
    ? await sql<{ workspace_id: string; owner: string | null }[]>`
        SELECT workspace_id, ${sql(spec.idColumn)} AS owner FROM ${sql(spec.table)} WHERE id = ${requestedId} FOR UPDATE`
    : [];
  if (existing && existing.workspace_id !== workspaceId) {
    throw new RpcError("permission-denied", "Record is not available in this workspace");
  }
  const id = requestedId || newDocId();
  const paid = kind === "worker" ? sql`, paid_amount = ${paidAmount}` : sql``;
  if (existing) {
    await sql`
      UPDATE ${sql(spec.table)} SET
        project_id = ${projectId}, ${sql(spec.idColumn)} = ${ownerId}, ${sql(spec.nameColumn)} = ${ownerName},
        description = ${description}, amount = ${amount}, date = ${date}, payment_method = ${paymentMethod},
        payment_status = ${paymentStatus}, notes = ${notes}${paid},
        attachments = COALESCE(${attachments === null ? null : sql.json(attachments as never)}, attachments),
        updated_at = now()
      WHERE id = ${id}`;
  } else {
    await sql`
      INSERT INTO ${sql(spec.table)} (id, workspace_id, project_id, ${sql(spec.idColumn)}, ${sql(spec.nameColumn)},
        description, amount, date, payment_method, payment_status, notes, attachments)
      VALUES (${id}, ${workspaceId}, ${projectId}, ${ownerId}, ${ownerName}, ${description}, ${amount}, ${date},
        ${paymentMethod}, ${paymentStatus}, ${notes}, ${sql.json((attachments ?? []) as never)})`;
    if (kind === "worker") {
      await sql`UPDATE worker_accounting_records SET paid_amount = ${paidAmount} WHERE id = ${id}`;
    }
  }
  if (kind === "worker") {
    await recomputeWorkerAccounting(sql, workspaceId, ownerId);
    if (existing?.owner && existing.owner !== ownerId) {
      await recomputeWorkerAccounting(sql, workspaceId, existing.owner);
    }
  }
  return { id };
}

const upsert = (kind: AccountingKind) => ({
  mutating: true,
  handler: (ctx: { sql: Sql; uid: string }, data: unknown) => upsertAccountingRecordForUser(ctx.sql, ctx.uid, kind, asRecord(data)),
});

export const accountingRecordRpcs: RpcRegistry = {
  upsertWorkerAccountingRecord: upsert("worker"),
  upsertContractorAccountingRecord: upsert("contractor"),
  upsertEquipmentAccountingRecord: upsert("equipment"),
  upsertTransportProviderAccountingRecord: upsert("transport"),
};
