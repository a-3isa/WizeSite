import { roleForUser } from "../auth/roles";
import type { Sql } from "../db/pool";
import { RpcError } from "../domain/errors";
import type { RpcRegistry } from "./types";
import { asRecord, requireString } from "./validation";

/**
 * restoreMembership replaces SessionRestoreService._ensureOwnerMembership, which tried to write the
 * owner's membership from the app (firestore.rules refused it; memberships are server-only). The
 * workspace owner gets the missing membership back; anyone else is refused.
 */
export async function restoreMembershipForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<{ workspaceId: string; restored: boolean }> {
  const workspaceId = requireString(data, "workspaceId");
  if (await roleForUser(sql, workspaceId, uid)) {
    return { workspaceId, restored: false };
  }
  const [ws] = await sql<{ owner_uid: string }[]>`SELECT owner_uid FROM workspaces WHERE id = ${workspaceId}`;
  if (!ws || ws.owner_uid !== uid) {
    throw new RpcError("permission-denied", "User is not a member of this workspace");
  }
  await sql`
    INSERT INTO memberships (id, workspace_id, user_uid, role)
    VALUES (${`${workspaceId}_${uid}`}, ${workspaceId}, ${uid}, 'owner')
    ON CONFLICT (workspace_id, user_uid) DO NOTHING`;
  return { workspaceId, restored: true };
}

export const sessionRpcs: RpcRegistry = {
  restoreMembership: {
    mutating: true,
    handler: (ctx, data) => restoreMembershipForUser(ctx.sql, ctx.uid, asRecord(data)),
  },
};
