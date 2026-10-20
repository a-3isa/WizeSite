import { assertCanMutateMoney } from "../auth/roles";
import type { Sql } from "../db/pool";
import { RpcError as HttpsError } from "../domain/errors";
import { isAllowedExpenseCategory, normalizeExpenseCategory, parsePaymentStatus } from "../domain/money";
import { recomputeProject } from "../recompute/persist";
import { assertAmountMatchesItems, type ExpenseItem, parseExpenseItems } from "./expense_items";
import { consumeMonthly, refundMonthly } from "./quota";
import { ensureAttachmentItems, existingMutation, legacyFields, mutationIdOf, toDate } from "./records";
import type { RpcRegistry } from "./types";
import { asRecord, newDocId, requireMoney, requireString, text } from "./validation";

/**
 * Expense RPCs ported from functions/src/index.ts (createExpenseWithQuotaForUser, updateExpense,
 * archiveExpenseWithQuotaRefundForUser). The Firestore versions applied metric deltas; here the
 * affected projects are recomputed from rows in the same transaction.
 */

type ProjectRow = { workspace_id: string; is_archived: boolean; name: string };

/** Project must exist, be in this workspace and not be archived (create and update). */
async function liveProject(sql: Sql, projectId: string, workspaceId: string): Promise<ProjectRow> {
  const [project] = await sql<ProjectRow[]>`
    SELECT workspace_id, is_archived, name FROM projects WHERE id = ${projectId}`;
  if (!project) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  if (project.workspace_id !== workspaceId || project.is_archived) {
    throw new HttpsError("permission-denied", "Project is not available in this workspace");
  }
  return project;
}

function validCategory(data: Record<string, unknown>): string {
  const categoryRaw = requireString(data, "category");
  if (!isAllowedExpenseCategory(categoryRaw)) {
    throw new HttpsError("invalid-argument", "Unsupported expense category");
  }
  return normalizeExpenseCategory(categoryRaw);
}

function positiveAmount(data: Record<string, unknown>): number {
  const amount = requireMoney(data, "amount");
  if (amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be greater than zero");
  }
  return amount;
}

/**
 * Feature 005: with items the total is their sum (an `amount` sent alongside must match); without
 * items (legacy payload) the amount is validated as before.
 */
function amountAndItems(data: Record<string, unknown>): { amount: number; items: ExpenseItem[] | null } {
  const parsed = parseExpenseItems(data);
  if (!parsed) {
    return { amount: positiveAmount(data), items: null };
  }
  const sent = data.amount === undefined || data.amount === null ? null : requireMoney(data, "amount");
  assertAmountMatchesItems(sent, parsed.total);
  return { amount: parsed.total, items: parsed.items };
}

/** The items CHECK can only fail on a server bug: log it and never show it as a user error. */
async function withItemsIntegrity<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    if ((error as { code?: string }).code === "23514") {
      console.error("expense items integrity check failed", { constraint: (error as { constraint_name?: string }).constraint_name });
      throw new HttpsError("internal", "Expense items integrity check failed");
    }
    throw error;
  }
}

export async function createExpenseWithQuotaForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<{ id: string; clientMutationId?: string }> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const projectId = requireString(data, "projectId");
  const category = validCategory(data);
  const { amount, items } = amountAndItems(data);
  const project = await liveProject(sql, projectId, workspaceId);

  const currencyRaw = text(data, "currency", "EGP").toUpperCase();
  const currency = ["EGP", "USD", "SAR", "AED"].includes(currencyRaw) ? currencyRaw : "EGP";
  const inputMethod = text(data, "inputMethod", "manual").toLowerCase();
  if (inputMethod !== "manual" && inputMethod !== "voice" && inputMethod !== "text") {
    throw new HttpsError("invalid-argument", "inputMethod must be manual, voice or text");
  }
  const sourceRaw = text(data, "source").toLowerCase();
  // Firestore stored null for anything else; the column is NOT NULL, and '' reads back the same.
  const source = sourceRaw === "rules" || sourceRaw === "llm" || sourceRaw === "hybrid" ? sourceRaw : "";
  const attachments = ensureAttachmentItems(data, "attachments");
  const clientMutationId = mutationIdOf(data);

  const replay = await existingMutation(sql, "expenses", workspaceId, clientMutationId);
  if (replay) {
    return replay;
  }
  await consumeMonthly(sql, workspaceId, "expensesPerMonth");

  const id = newDocId();
  await sql`
    INSERT INTO expenses (id, workspace_id, project_id, project_name, amount, currency, date, category,
                          description, notes, purpose, payment_method, payment_status, entity_id, entity_type,
                          entity_name, supplier_name, input_method, source, transcript, storage_path,
                          attachments, items, is_archived, client_mutation_id, created_by, legacy)
    VALUES (${id}, ${workspaceId}, ${projectId}, ${text(data, "projectName") || `${project.name ?? ""}`.trim()},
            ${amount}, ${currency}, ${toDate(data.date) ?? new Date()}, ${category},
            ${`${data.description ?? data.notes ?? ""}`.trim()}, ${text(data, "notes")}, ${text(data, "purpose")},
            ${text(data, "paymentMethod")}, ${parsePaymentStatus(data.paymentStatus, "unpaid")},
            ${text(data, "entityId") || null}, ${text(data, "entityType", "supplier")},
            ${`${data.entityName ?? data.supplierName ?? ""}`.trim()}, ${text(data, "supplierName")},
            ${inputMethod}, ${source}, ${text(data, "transcript")}, ${text(data, "storagePath")},
            ${sql.json(attachments as never)}, ${sql.json((items ?? []) as never)}, false, ${clientMutationId}, ${uid},
            ${sql.json(legacyFields(data) as never)})`;
  await recomputeProject(sql, workspaceId, projectId);
  return { id, clientMutationId: clientMutationId ?? "" };
}

type ExpenseRow = { workspace_id: string; project_id: string; is_archived: boolean; items: ExpenseItem[] };

async function expenseInWorkspace(sql: Sql, expenseId: string, workspaceId: string): Promise<ExpenseRow> {
  const [expense] = await sql<ExpenseRow[]>`
    SELECT workspace_id, project_id, is_archived, items FROM expenses WHERE id = ${expenseId} FOR UPDATE`;
  if (!expense) {
    throw new HttpsError("not-found", "Expense not found");
  }
  if (expense.workspace_id !== workspaceId) {
    throw new HttpsError("permission-denied", "Expense is not available in this workspace");
  }
  return expense;
}

export async function updateExpenseForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const expenseId = requireString(data, "expenseId");
  const projectId = requireString(data, "projectId");
  const category = validCategory(data);
  const sent = amountAndItems(data);

  const expense = await expenseInWorkspace(sql, expenseId, workspaceId);
  if (expense.is_archived) {
    throw new HttpsError("failed-precondition", "Archived expenses cannot be edited.");
  }
  await liveProject(sql, projectId, workspaceId);
  // Only replace attachments when the caller sent them (data.attachments != null).
  const attachments = data.attachments != null ? ensureAttachmentItems(data, "attachments") : null;
  // Without items (legacy payload, contract §2) the stored items decide: a legacy row keeps [],
  // a single item follows the new amount, and several items cannot absorb one amount.
  const stored = Array.isArray(expense.items) ? expense.items : [];
  let items: ExpenseItem[] | null = sent.items;
  if (!items && stored.length === 1) {
    items = [{ ...stored[0], amount: sent.amount }];
  } else if (!items && stored.length > 1) {
    throw new HttpsError("failed-precondition", "This expense has several items; edit its items to change the amount");
  }
  // The title is saved only when the caller sent one (it was ignored before feature 005).
  const description = typeof data.description === "string" ? data.description.trim() : null;

  await sql`
    UPDATE expenses SET
      project_id = ${projectId},
      category = ${category},
      amount = ${sent.amount},
      items = COALESCE(${items === null ? null : sql.json(items as never)}, items),
      description = COALESCE(${description}, description),
      date = ${toDate(data.date) ?? new Date()},
      notes = ${text(data, "notes")},
      supplier_name = ${text(data, "supplierName")},
      payment_method = ${text(data, "paymentMethod")},
      payment_status = ${parsePaymentStatus(data.paymentStatus, "unpaid")},
      client_mutation_id = ${mutationIdOf(data)},
      attachments = COALESCE(${attachments === null ? null : sql.json(attachments as never)}, attachments),
      legacy = legacy || ${sql.json(legacyFields({ clientUpdatedAt: data.clientUpdatedAt }) as never)},
      updated_at = now()
    WHERE id = ${expenseId}`;
  await recomputeProject(sql, workspaceId, projectId);
  if (expense.project_id && expense.project_id !== projectId) {
    await recomputeProject(sql, workspaceId, expense.project_id);
  }
}

export async function archiveExpenseWithQuotaRefundForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const expenseId = requireString(data, "expenseId");
  const expense = await expenseInWorkspace(sql, expenseId, workspaceId);
  if (expense.is_archived) {
    return;
  }
  await sql`UPDATE expenses SET is_archived = true, archived_at = now(), updated_at = now() WHERE id = ${expenseId}`;
  await refundMonthly(sql, workspaceId, "expensesPerMonth");
  if (expense.project_id) {
    await recomputeProject(sql, workspaceId, expense.project_id);
  }
}

export const expenseRpcs: RpcRegistry = {
  createExpenseWithQuota: {
    mutating: true,
    handler: (ctx, data) => withItemsIntegrity(() => createExpenseWithQuotaForUser(ctx.sql, ctx.uid, asRecord(data))),
  },
  updateExpense: {
    mutating: true,
    handler: async (ctx, data) => {
      await withItemsIntegrity(() => updateExpenseForUser(ctx.sql, ctx.uid, asRecord(data)));
      return null;
    },
  },
  archiveExpenseWithQuotaRefund: {
    mutating: true,
    handler: async (ctx, data) => {
      await archiveExpenseWithQuotaRefundForUser(ctx.sql, ctx.uid, asRecord(data));
      return null;
    },
  },
};
