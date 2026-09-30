import { assertInWorkspace, assertMember } from "../auth/roles";
import type { Sql } from "../db/pool";
import type { TriggerDocData } from "../domain/accounting";
import { RpcError } from "../domain/errors";
import { rowToDoc } from "../recompute/rows";
import { ensureAttachmentItems, mutationIdOf } from "./records";
import type { RpcRegistry } from "./types";
import { asRecord, assertTwoDecimals, newDocId, requireString, text } from "./validation";

/**
 * Contact directory writes that the app made directly against Firestore
 * (entity_repository.dart: ensureEntity, createEntity, updateEntity, deleteEntity, saveAttachments).
 *
 * firestore.rules let any workspace member create and edit contacts, but its update allow-list
 * left out phoneNumber, notes and rateUnit and it refused deletes, so those app actions failed.
 * Here edits follow the app (any member), and deleting is limited to owners and admins.
 */

/** EntityRepository.normalizeName. */
export function normalizeName(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, " ");
}

const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

async function entityDoc(sql: Sql, id: string): Promise<TriggerDocData> {
  const [row] = await sql<Record<string, unknown>[]>`SELECT * FROM entities WHERE id = ${id}`;
  return rowToDoc(row);
}

function optionalText(data: Record<string, unknown>, key: string): string | null {
  const value = `${data[key] ?? ""}`.trim();
  return value.length > 0 ? value : null;
}

/**
 * Creates the contact, or updates it when `id` names an existing one in this workspace. Returns
 * the contact in its document shape, as the app read it back after writing.
 */
export async function upsertEntityForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<TriggerDocData> {
  const workspaceId = requireString(data, "workspaceId");
  await assertInWorkspace(sql, workspaceId, uid);
  const name = requireString(data, "name");
  const type = text(data, "type", "supplier") || "supplier";
  const rawRate = data.defaultRate;
  const defaultRate =
    rawRate === undefined || rawRate === null || `${rawRate}`.trim() === ""
      ? null
      : assertTwoDecimals(Number(rawRate), "defaultRate");
  if (defaultRate !== null && !Number.isFinite(defaultRate)) {
    throw new RpcError("invalid-argument", "Invalid number: defaultRate");
  }
  const attachments = data.attachments != null ? ensureAttachmentItems(data, "attachments") : null;

  const requestedId = `${data.id ?? ""}`.trim();
  if (requestedId && !ID_PATTERN.test(requestedId)) {
    throw new RpcError("invalid-argument", "Invalid entity id");
  }
  const [existing] = requestedId
    ? await sql<{ workspace_id: string }[]>`SELECT workspace_id FROM entities WHERE id = ${requestedId} FOR UPDATE`
    : [];
  if (existing && existing.workspace_id !== workspaceId) {
    throw new RpcError("permission-denied", "Entity is not available in this workspace");
  }

  if (existing) {
    await sql`
      UPDATE entities SET
        name = ${name}, normalized_name = ${normalizeName(name)}, type = ${type}, default_rate = ${defaultRate},
        rate_unit = ${optionalText(data, "rateUnit")}, phone_number = ${optionalText(data, "phoneNumber") ?? ""},
        notes = ${optionalText(data, "notes") ?? ""},
        attachments = COALESCE(${attachments === null ? null : sql.json(attachments as never)}, attachments),
        last_used_at = now(), updated_at = now()
      WHERE id = ${requestedId}`;
    return entityDoc(sql, requestedId);
  }
  const id = requestedId || newDocId();
  await sql`
    INSERT INTO entities (id, workspace_id, type, name, normalized_name, phone_number, notes, default_rate, rate_unit,
                          attachments, last_used_at, client_mutation_id)
    VALUES (${id}, ${workspaceId}, ${type}, ${name}, ${normalizeName(name)}, ${optionalText(data, "phoneNumber") ?? ""},
            ${optionalText(data, "notes") ?? ""}, ${defaultRate}, ${optionalText(data, "rateUnit")},
            ${sql.json((attachments ?? []) as never)}, now(), ${mutationIdOf(data)})`;
  return entityDoc(sql, id);
}

async function entityInWorkspace(sql: Sql, workspaceId: string, entityId: string): Promise<void> {
  const [entity] = await sql<{ workspace_id: string }[]>`
    SELECT workspace_id FROM entities WHERE id = ${entityId} FOR UPDATE`;
  if (!entity) {
    throw new RpcError("not-found", "Entity not found");
  }
  if (entity.workspace_id !== workspaceId) {
    throw new RpcError("permission-denied", "Entity is not available in this workspace");
  }
}

export async function touchEntityLastUsedForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertInWorkspace(sql, workspaceId, uid);
  const entityId = requireString(data, "entityId");
  await entityInWorkspace(sql, workspaceId, entityId);
  await sql`UPDATE entities SET last_used_at = now(), updated_at = now() WHERE id = ${entityId}`;
}

export async function archiveEntityForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertInWorkspace(sql, workspaceId, uid);
  const entityId = requireString(data, "entityId");
  await entityInWorkspace(sql, workspaceId, entityId);
  await sql`UPDATE entities SET is_archived = true, updated_at = now() WHERE id = ${entityId}`;
}

/** Records keep their copied entity name; only the directory entry goes. */
export async function deleteEntityForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  const role = await assertMember(sql, workspaceId, uid);
  if (role !== "owner" && role !== "admin") {
    throw new RpcError("permission-denied", "Only owners and admins can delete contacts");
  }
  const entityId = requireString(data, "entityId");
  await entityInWorkspace(sql, workspaceId, entityId);
  await sql`DELETE FROM entities WHERE id = ${entityId}`;
}

const done = (fn: (sql: Sql, uid: string, data: Record<string, unknown>) => Promise<void>) => ({
  mutating: true,
  handler: async (ctx: { sql: Sql; uid: string }, data: unknown) => {
    await fn(ctx.sql, ctx.uid, asRecord(data));
    return null;
  },
});

export const entityRpcs: RpcRegistry = {
  upsertEntity: {
    mutating: true,
    handler: (ctx, data) => upsertEntityForUser(ctx.sql, ctx.uid, asRecord(data)),
  },
  touchEntityLastUsed: done(touchEntityLastUsedForUser),
  archiveEntity: done(archiveEntityForUser),
  deleteEntity: done(deleteEntityForUser),
};
