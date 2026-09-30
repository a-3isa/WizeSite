import { roleForUser } from "../auth/roles";
import type { Sql } from "../db/pool";
import { RpcError } from "../domain/errors";
import type { RpcRegistry } from "./types";
import { asRecord } from "./validation";

/**
 * markNotificationsRead replaces NotificationRepository.markRead's batch update. As with the
 * rules (target user, still in the workspace, only readAt) and the batch, it is all or nothing.
 */
export async function markNotificationsReadForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<{ updated: number }> {
  const raw = Array.isArray(data.notificationIds) ? data.notificationIds : [];
  const ids = [...new Set(raw.map((id) => `${id ?? ""}`.trim()).filter(Boolean))];
  if (ids.length === 0) {
    return { updated: 0 };
  }
  if (ids.length > 500) {
    throw new RpcError("invalid-argument", "Too many notifications");
  }
  const rows = await sql<{ id: string; workspace_id: string | null; target_user_id: string }[]>`
    SELECT id, workspace_id, target_user_id FROM notifications WHERE id IN ${sql(ids)} FOR UPDATE`;
  const workspaces = new Map<string, boolean>();
  for (const id of ids) {
    const row = rows.find((r) => r.id === id);
    if (!row || row.target_user_id !== uid) {
      throw new RpcError("permission-denied", "Notification is not available");
    }
    const workspaceId = `${row.workspace_id ?? ""}`;
    if (!workspaces.has(workspaceId)) {
      const [owner] = await sql`SELECT 1 FROM workspaces WHERE id = ${workspaceId} AND owner_uid = ${uid}`;
      workspaces.set(workspaceId, Boolean(owner) || (await roleForUser(sql, workspaceId, uid)) !== null);
    }
    if (!workspaces.get(workspaceId)) {
      throw new RpcError("permission-denied", "Notification is not available");
    }
  }
  await sql`UPDATE notifications SET read_at = now(), updated_at = now() WHERE id IN ${sql(ids)}`;
  return { updated: ids.length };
}

export const notificationRpcs: RpcRegistry = {
  markNotificationsRead: {
    mutating: true,
    handler: (ctx, data) => markNotificationsReadForUser(ctx.sql, ctx.uid, asRecord(data)),
  },
};
