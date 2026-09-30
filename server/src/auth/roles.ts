import type { Sql } from "../db/pool";
import { RpcError } from "../domain/errors";
import { canMutateMoneyViaCallable, canUpdateProject } from "../domain/money";

/**
 * Postgres port of `roleForUser` / `assertMember` from functions/src/index.ts.
 * Membership = a row exists (same as firestore.rules `hasMembership`). Role predicates
 * (canMutateMoneyViaCallable, canUpdateProject, ...) live in src/domain/money.ts.
 */
export async function roleForUser(
  sql: Sql,
  workspaceId: string,
  uid: string,
): Promise<string | null> {
  if (!workspaceId || !uid) {
    return null;
  }
  const rows = await sql<{ role: string | null }[]>`
    SELECT role FROM memberships
    WHERE workspace_id = ${workspaceId} AND user_uid = ${uid}
    LIMIT 1`;
  if (rows.length === 0) {
    return null;
  }
  return `${rows[0].role ?? "member"}`;
}

export async function assertMember(sql: Sql, workspaceId: string, uid: string): Promise<string> {
  const role = await roleForUser(sql, workspaceId, uid);
  if (!role) {
    throw new RpcError("permission-denied", "User is not a member of this workspace");
  }
  return role;
}

/** assertCanMutateMoney: every member except entryOnly may change money records. */
export async function assertCanMutateMoney(sql: Sql, workspaceId: string, uid: string): Promise<string> {
  const role = await assertMember(sql, workspaceId, uid);
  if (!canMutateMoneyViaCallable(role)) {
    throw new RpcError("permission-denied", "Accounting access required");
  }
  return role;
}

/** assertCanManageProject: update/archive/unarchive a project. */
export async function assertCanManageProject(sql: Sql, workspaceId: string, uid: string): Promise<string> {
  const role = await assertMember(sql, workspaceId, uid);
  if (!canUpdateProject(role)) {
    throw new RpcError("permission-denied", "Not allowed to manage project");
  }
  return role;
}

async function isWorkspaceOwner(sql: Sql, workspaceId: string, uid: string): Promise<boolean> {
  const rows = await sql`SELECT 1 FROM workspaces WHERE id = ${workspaceId} AND owner_uid = ${uid}`;
  return rows.length > 0;
}

/** firestore.rules inWorkspace: a membership, or the workspace's owner. */
export async function assertInWorkspace(sql: Sql, workspaceId: string, uid: string): Promise<void> {
  if ((await roleForUser(sql, workspaceId, uid)) === null && !(await isWorkspaceOwner(sql, workspaceId, uid))) {
    throw new RpcError("permission-denied", "User is not a member of this workspace");
  }
}

/** firestore.rules canAccessAccounting: the owner, or owner/admin/accountingApproved members. */
export async function assertCanAccessAccounting(sql: Sql, workspaceId: string, uid: string): Promise<void> {
  const role = await roleForUser(sql, workspaceId, uid);
  if (role !== null && ["owner", "admin", "accountingApproved"].includes(role)) {
    return;
  }
  if (await isWorkspaceOwner(sql, workspaceId, uid)) {
    return;
  }
  throw new RpcError("permission-denied", "Accounting access required");
}
