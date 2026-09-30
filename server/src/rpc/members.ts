import { assertMember, roleForUser } from "../auth/roles";
import type { Sql } from "../db/pool";
import { RpcError } from "../domain/errors";
import { upsertNotificationForUsers } from "./notify";
import { hasUnlimitedQuota, limitForType, type LimitType, periodKey, quotaError } from "./quota";
import type { RpcRegistry } from "./types";
import { asRecord, newDocId, normalizeEmail, requireString } from "./validation";

/**
 * Workspace setup and team RPCs ported from functions/src/index.ts
 * (completeInitialWorkspaceSetupForUser, createWorkspaceForUser, updateWorkspaceMemberRoleForUser,
 * removeWorkspaceMemberForUser, inviteMemberByEmailForUser, inviteMemberWithQuotaForUser,
 * checkLimit). Same messages and role rules.
 */

const SUPPORTED_CURRENCIES = ["EGP", "USD", "SAR", "AED", "KWD", "QAR", "BHD", "OMR", "JOD"];

function requireCurrencyCode(input: unknown): string {
  const raw = `${input ?? ""}`.trim().toUpperCase();
  if (!SUPPORTED_CURRENCIES.includes(raw)) {
    throw new RpcError("invalid-argument", "Unsupported currency");
  }
  return raw;
}

async function setOwnerProfile(sql: Sql, uid: string, workspaceId: string, defaultCurrency: string): Promise<void> {
  await sql`
    INSERT INTO user_profiles (uid, active_workspace_id, default_currency, setup_completed)
    VALUES (${uid}, ${workspaceId}, ${defaultCurrency}, true)
    ON CONFLICT (uid) DO UPDATE SET active_workspace_id = EXCLUDED.active_workspace_id,
      default_currency = EXCLUDED.default_currency, setup_completed = true, updated_at = now()`;
}

async function upsertOwnerMembership(sql: Sql, workspaceId: string, uid: string): Promise<void> {
  await sql`
    INSERT INTO memberships (id, workspace_id, user_uid, role)
    VALUES (${`${workspaceId}_${uid}`}, ${workspaceId}, ${uid}, 'owner')
    ON CONFLICT (workspace_id, user_uid) DO UPDATE SET role = 'owner', updated_at = now()`;
}

export async function completeInitialWorkspaceSetupForUser(
  sql: Sql,
  input: { uid: string; workspaceId: string; workspaceName: string; defaultCurrency: string },
): Promise<{ workspaceId: string; setupCompleted: boolean }> {
  const uid = input.uid.trim();
  const workspaceId = input.workspaceId.trim();
  const workspaceName = input.workspaceName.trim();
  const defaultCurrency = requireCurrencyCode(input.defaultCurrency);
  if (!uid || !workspaceId) {
    throw new RpcError("invalid-argument", "Missing workspace setup target");
  }
  if (!workspaceName) {
    throw new RpcError("invalid-argument", "Missing workspace name");
  }
  const [ws] = await sql<{ owner_uid: string }[]>`SELECT owner_uid FROM workspaces WHERE id = ${workspaceId}`;
  if (!ws) {
    throw new RpcError("not-found", "Workspace not found");
  }
  if (ws.owner_uid !== uid) {
    throw new RpcError("permission-denied", "Only the workspace owner can complete setup");
  }
  await sql`UPDATE workspaces SET name = ${workspaceName}, updated_at = now() WHERE id = ${workspaceId}`;
  await setOwnerProfile(sql, uid, workspaceId, defaultCurrency);
  await upsertOwnerMembership(sql, workspaceId, uid);
  return { workspaceId, setupCompleted: true };
}

/** An owner on Pro may add workspaces; new ones start on the free plan (no Pro snapshot copied). */
export async function createWorkspaceForUser(
  sql: Sql,
  input: { uid: string; sourceWorkspaceId: string; workspaceName: string; defaultCurrency: string },
): Promise<{ workspaceId: string; created: boolean }> {
  const uid = input.uid.trim();
  const sourceWorkspaceId = input.sourceWorkspaceId.trim();
  const workspaceName = input.workspaceName.trim();
  const defaultCurrency = requireCurrencyCode(input.defaultCurrency);
  if (!uid || !sourceWorkspaceId) {
    throw new RpcError("invalid-argument", "Missing source workspace");
  }
  if (!workspaceName) {
    throw new RpcError("invalid-argument", "Missing workspace name");
  }
  if ((await assertMember(sql, sourceWorkspaceId, uid)) !== "owner") {
    throw new RpcError("permission-denied", "Only the workspace owner can create additional workspaces");
  }
  if (!(await hasUnlimitedQuota(sql, sourceWorkspaceId))) {
    throw new RpcError("failed-precondition", "Upgrade to Pro to create additional workspaces");
  }
  const workspaceId = newDocId();
  await sql`INSERT INTO workspaces (id, owner_uid, name) VALUES (${workspaceId}, ${uid}, ${workspaceName})`;
  await upsertOwnerMembership(sql, workspaceId, uid);
  await setOwnerProfile(sql, uid, workspaceId, defaultCurrency);
  return { workspaceId, created: true };
}

const WORKSPACE_ROLES = ["owner", "admin", "accountingApproved", "member", "entryOnly"];

async function ownerCount(sql: Sql, workspaceId: string): Promise<number> {
  const [{ count }] = await sql<{ count: number }[]>`
    SELECT count(*)::int AS count FROM memberships WHERE workspace_id = ${workspaceId} AND role = 'owner'`;
  return count;
}

async function assertWorkspaceOwner(sql: Sql, workspaceId: string, uid: string): Promise<void> {
  if ((await assertMember(sql, workspaceId, uid)) !== "owner") {
    throw new RpcError("permission-denied", "Only owner can manage members");
  }
}

async function lockedMemberRole(sql: Sql, workspaceId: string, userId: string): Promise<string> {
  const [m] = await sql<{ role: string | null }[]>`
    SELECT role FROM memberships WHERE workspace_id = ${workspaceId} AND user_uid = ${userId} FOR UPDATE`;
  if (!m) {
    throw new RpcError("not-found", "Workspace member not found");
  }
  return `${m.role ?? "member"}`;
}

export async function updateWorkspaceMemberRoleForUser(
  sql: Sql,
  input: { ownerUid: string; workspaceId: string; targetUserId: string; role: string },
): Promise<{ userId: string; workspaceId: string; role: string }> {
  const workspaceId = input.workspaceId.trim();
  const targetUserId = input.targetUserId.trim();
  const role = input.role.trim();
  if (!workspaceId || !targetUserId || !role) {
    throw new RpcError("invalid-argument", "Missing member role update");
  }
  if (!WORKSPACE_ROLES.includes(role)) {
    throw new RpcError("invalid-argument", "Unsupported workspace role");
  }
  await assertWorkspaceOwner(sql, workspaceId, input.ownerUid.trim());
  const currentRole = await lockedMemberRole(sql, workspaceId, targetUserId);
  if (currentRole === "owner" && role !== "owner" && (await ownerCount(sql, workspaceId)) <= 1) {
    throw new RpcError("failed-precondition", "Workspace must keep at least one owner");
  }
  await sql`UPDATE memberships SET role = ${role}, updated_at = now()
            WHERE workspace_id = ${workspaceId} AND user_uid = ${targetUserId}`;
  return { userId: targetUserId, workspaceId, role };
}

export async function removeWorkspaceMemberForUser(
  sql: Sql,
  input: { ownerUid: string; workspaceId: string; targetUserId: string },
): Promise<{ userId: string; workspaceId: string; removed: boolean }> {
  const workspaceId = input.workspaceId.trim();
  const targetUserId = input.targetUserId.trim();
  if (!workspaceId || !targetUserId) {
    throw new RpcError("invalid-argument", "Missing member removal target");
  }
  await assertWorkspaceOwner(sql, workspaceId, input.ownerUid.trim());
  const currentRole = await lockedMemberRole(sql, workspaceId, targetUserId);
  if (currentRole === "owner" && (await ownerCount(sql, workspaceId)) <= 1) {
    throw new RpcError("failed-precondition", "Workspace must keep at least one owner");
  }
  await sql`DELETE FROM memberships WHERE workspace_id = ${workspaceId} AND user_uid = ${targetUserId}`;
  return { userId: targetUserId, workspaceId, removed: true };
}

const ENFORCE_TEAM_MEMBER_LIMITS = true;

async function teamMemberCount(sql: Sql, workspaceId: string): Promise<number> {
  const [{ count }] = await sql<{ count: number }[]>`
    SELECT count(*)::int AS count FROM memberships WHERE workspace_id = ${workspaceId}`;
  return count;
}

/** Adds the member plus the "Workspace Access Granted" notification (both invite paths). */
async function addInvitedMember(
  sql: Sql,
  input: { ownerUid: string; workspaceId: string; userId: string; role: string },
): Promise<void> {
  if (ENFORCE_TEAM_MEMBER_LIMITS && !(await hasUnlimitedQuota(sql, input.workspaceId))) {
    // Serialise invites to one workspace so the team limit holds under concurrency.
    await sql`SELECT id FROM workspaces WHERE id = ${input.workspaceId} FOR UPDATE`;
    const current = await teamMemberCount(sql, input.workspaceId);
    const max = limitForType("teamMembers");
    if (current + 1 > max) {
      quotaError("teamMembers", current, max);
    }
  }
  await sql`
    INSERT INTO memberships (id, workspace_id, user_uid, role, invited_by, legacy)
    VALUES (${`${input.workspaceId}_${input.userId}`}, ${input.workspaceId}, ${input.userId}, ${input.role},
            ${input.ownerUid}, ${sql.json({ createdBy: input.ownerUid } as never)})`;
  await upsertNotificationForUsers(sql, {
    workspaceId: input.workspaceId,
    userIds: [input.userId],
    type: "team_invite_added",
    title: "Workspace Access Granted",
    message: "You were added to a workspace team.",
  });
}

function inviteRole(role: string | undefined): string {
  const value = `${role ?? "member"}`.trim() || "member";
  if (!WORKSPACE_ROLES.includes(value)) {
    throw new RpcError("invalid-argument", "Unsupported workspace role");
  }
  return value;
}

/** An unknown email and an existing member look the same to the caller (INVITE_UNAVAILABLE). */
export async function inviteMemberByEmailForUser(
  sql: Sql,
  input: { ownerUid: string; workspaceId: string; email: string; role?: string },
): Promise<{ userId: string; workspaceId: string }> {
  const ownerUid = input.ownerUid.trim();
  const workspaceId = input.workspaceId.trim();
  if ((await assertMember(sql, workspaceId, ownerUid)) !== "owner") {
    throw new RpcError("permission-denied", "Only owner can invite members");
  }
  const email = normalizeEmail(input.email);
  if (!email) {
    throw new RpcError("invalid-argument", "Missing required field: email");
  }
  const role = inviteRole(input.role);
  const [user] = await sql<{ uid: string }[]>`SELECT uid FROM user_profiles WHERE email = ${email} LIMIT 1`;
  if (!user) {
    throw new RpcError("not-found", "INVITE_UNAVAILABLE");
  }
  if (await roleForUser(sql, workspaceId, user.uid)) {
    throw new RpcError("not-found", "INVITE_UNAVAILABLE");
  }
  await addInvitedMember(sql, { ownerUid, workspaceId, userId: user.uid, role });
  return { userId: user.uid, workspaceId };
}

export async function inviteMemberWithQuotaForUser(
  sql: Sql,
  input: { ownerUid: string; workspaceId: string; userId: string; role?: string },
): Promise<{ userId: string; workspaceId: string }> {
  const ownerUid = input.ownerUid.trim();
  const workspaceId = input.workspaceId.trim();
  if ((await assertMember(sql, workspaceId, ownerUid)) !== "owner") {
    throw new RpcError("permission-denied", "Only owner can invite members");
  }
  const newUserId = input.userId.trim();
  if (!newUserId) {
    throw new RpcError("invalid-argument", "Missing required field: userId");
  }
  const role = inviteRole(input.role);
  if (await roleForUser(sql, workspaceId, newUserId)) {
    throw new RpcError("already-exists", "User is already a member of this workspace");
  }
  await addInvitedMember(sql, { ownerUid, workspaceId, userId: newUserId, role });
  return { userId: newUserId, workspaceId };
}

const LIMIT_TYPES: LimitType[] = ["activeProjects", "expensesPerMonth", "paymentsPerMonth", "workerEntriesPerMonth", "teamMembers"];

function nextResetIso(now = new Date()): string {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1)).toISOString();
}

/** getCurrentUsage: counters as stored; activeProjects falls back to a live count. */
async function currentUsage(sql: Sql, workspaceId: string, type: LimitType): Promise<number> {
  if (type === "teamMembers") {
    return teamMemberCount(sql, workspaceId);
  }
  if (type === "activeProjects") {
    const [row] = await sql<{ value: number }[]>`
      SELECT active_projects AS value FROM usage_counters WHERE id = ${`${workspaceId}_projects`}`;
    if (row) {
      return Number(row.value);
    }
    const [{ count }] = await sql<{ count: number }[]>`
      SELECT count(*)::int AS count FROM projects
      WHERE workspace_id = ${workspaceId} AND status = 'active' AND NOT is_archived`;
    return count;
  }
  const column = {
    expensesPerMonth: "expenses_count",
    paymentsPerMonth: "payments_count",
    workerEntriesPerMonth: "worker_entries_count",
  }[type];
  const [row] = await sql<{ value: number }[]>`
    SELECT ${sql(column)} AS value FROM usage_counters WHERE id = ${`${workspaceId}_${periodKey()}`}`;
  return Number(row?.value ?? 0);
}

export async function checkLimitForUser(
  sql: Sql,
  uid: string,
  data: Record<string, unknown>,
): Promise<{ allowed: boolean; current: number; max: number; resetAt: string }> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(sql, workspaceId, uid);
  const type = requireString(data, "type") as LimitType;
  const delta = Math.max(1, Number(data.delta ?? 1));
  if (!LIMIT_TYPES.includes(type)) {
    throw new RpcError("invalid-argument", "Unsupported limit type");
  }
  if (await hasUnlimitedQuota(sql, workspaceId)) {
    return { allowed: true, current: 0, max: 999999, resetAt: nextResetIso() };
  }
  const current = await currentUsage(sql, workspaceId, type);
  const max = limitForType(type);
  return { allowed: current + delta <= max, current, max, resetAt: nextResetIso() };
}

export const memberRpcs: RpcRegistry = {
  completeInitialWorkspaceSetup: {
    mutating: true,
    handler: (ctx, data) => {
      const d = asRecord(data);
      return completeInitialWorkspaceSetupForUser(ctx.sql, {
        uid: ctx.uid,
        workspaceId: requireString(d, "workspaceId"),
        workspaceName: requireString(d, "workspaceName"),
        defaultCurrency: requireString(d, "defaultCurrency"),
      });
    },
  },
  createWorkspace: {
    mutating: true,
    handler: (ctx, data) => {
      const d = asRecord(data);
      return createWorkspaceForUser(ctx.sql, {
        uid: ctx.uid,
        sourceWorkspaceId: requireString(d, "sourceWorkspaceId"),
        workspaceName: requireString(d, "workspaceName"),
        defaultCurrency: requireString(d, "defaultCurrency"),
      });
    },
  },
  updateWorkspaceMemberRole: {
    mutating: true,
    handler: (ctx, data) => {
      const d = asRecord(data);
      return updateWorkspaceMemberRoleForUser(ctx.sql, {
        ownerUid: ctx.uid,
        workspaceId: requireString(d, "workspaceId"),
        targetUserId: requireString(d, "userId"),
        role: requireString(d, "role"),
      });
    },
  },
  removeWorkspaceMember: {
    mutating: true,
    handler: (ctx, data) => {
      const d = asRecord(data);
      return removeWorkspaceMemberForUser(ctx.sql, {
        ownerUid: ctx.uid,
        workspaceId: requireString(d, "workspaceId"),
        targetUserId: requireString(d, "userId"),
      });
    },
  },
  inviteMemberByEmail: {
    mutating: true,
    handler: (ctx, data) => {
      const d = asRecord(data);
      return inviteMemberByEmailForUser(ctx.sql, {
        ownerUid: ctx.uid,
        workspaceId: requireString(d, "workspaceId"),
        email: requireString(d, "email"),
        role: `${d.role ?? "member"}`,
      });
    },
  },
  inviteMemberWithQuota: {
    mutating: true,
    handler: (ctx, data) => {
      const d = asRecord(data);
      return inviteMemberWithQuotaForUser(ctx.sql, {
        ownerUid: ctx.uid,
        workspaceId: requireString(d, "workspaceId"),
        userId: requireString(d, "userId"),
        role: `${d.role ?? "member"}`,
      });
    },
  },
  checkLimit: {
    mutating: false,
    handler: (ctx, data) => checkLimitForUser(ctx.sql, ctx.uid, asRecord(data)),
  },
};
