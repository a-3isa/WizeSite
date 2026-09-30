/** T061: workspace and member RPCs ported from functions/src/index.ts. */
import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { withTransaction } from "../../src/db/tx";
import { periodKey } from "../../src/rpc/quota";
import {
  checkLimitForUser,
  completeInitialWorkspaceSetupForUser,
  createWorkspaceForUser,
  inviteMemberByEmailForUser,
  inviteMemberWithQuotaForUser,
  removeWorkspaceMemberForUser,
  updateWorkspaceMemberRoleForUser,
} from "../../src/rpc/members";
import { resetDatabase, seedWorkspace, skipReason, testSql } from "./helpers";

let sql: Sql;
before(() => {
  if (!skipReason) sql = testSql();
});
after(async () => {
  if (sql) await sql.end();
});
beforeEach(async () => {
  if (!skipReason) {
    await resetDatabase(sql);
    await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "u1", members: { admin1: "admin" } });
    await sql`INSERT INTO user_profiles (uid, email, active_workspace_id) VALUES
      ('u1', 'owner@example.com', 'ws_1'), ('friend', 'friend@example.com', NULL), ('admin1', 'a@example.com', 'ws_1')`;
  }
});

const tx = <T>(fn: (t: Sql) => Promise<T>) => withTransaction(sql, fn);
const pro = () => sql`INSERT INTO subscriptions (workspace_id, tier, status) VALUES ('ws_1', 'pro', 'active')`;
async function rejectsWith(promise: Promise<unknown>, code: string, message: string) {
  await assert.rejects(promise, (error: { code?: string; message?: string }) => {
    assert.equal(error.code, code);
    assert.equal(error.message, message);
    return true;
  });
}

test("completeInitialWorkspaceSetup: owner names the workspace; profile marked set up", { skip: skipReason }, async () => {
  await rejectsWith(
    tx((t) => completeInitialWorkspaceSetupForUser(t, { uid: "u1", workspaceId: "ws_1", workspaceName: "X", defaultCurrency: "XYZ" })),
    "invalid-argument",
    "Unsupported currency",
  );
  await rejectsWith(
    tx((t) => completeInitialWorkspaceSetupForUser(t, { uid: "admin1", workspaceId: "ws_1", workspaceName: "X", defaultCurrency: "EGP" })),
    "permission-denied",
    "Only the workspace owner can complete setup",
  );
  const result = await tx((t) =>
    completeInitialWorkspaceSetupForUser(t, { uid: "u1", workspaceId: "ws_1", workspaceName: " ورشتي ", defaultCurrency: "sar" }),
  );
  assert.deepEqual(result, { workspaceId: "ws_1", setupCompleted: true });
  const [ws] = await sql`SELECT name FROM workspaces WHERE id = 'ws_1'`;
  assert.equal(ws.name, "ورشتي");
  const [p] = await sql`SELECT default_currency, setup_completed, active_workspace_id FROM user_profiles WHERE uid = 'u1'`;
  assert.deepEqual({ ...p }, { default_currency: "SAR", setup_completed: true, active_workspace_id: "ws_1" });
});

test("createWorkspace: owner on Pro only; the new workspace starts free", { skip: skipReason }, async () => {
  const create = (uid: string) =>
    tx((t) => createWorkspaceForUser(t, { uid, sourceWorkspaceId: "ws_1", workspaceName: "Second", defaultCurrency: "EGP" }));
  await rejectsWith(create("admin1"), "permission-denied", "Only the workspace owner can create additional workspaces");
  await rejectsWith(create("u1"), "failed-precondition", "Upgrade to Pro to create additional workspaces");
  await pro();
  const { workspaceId, created } = await create("u1");
  assert.equal(created, true);
  const [m] = await sql`SELECT role FROM memberships WHERE workspace_id = ${workspaceId} AND user_uid = 'u1'`;
  assert.equal(m.role, "owner");
  const subs = await sql`SELECT 1 FROM subscriptions WHERE workspace_id = ${workspaceId}`;
  assert.equal(subs.length, 0, "no Pro snapshot copied");
  const [p] = await sql`SELECT active_workspace_id FROM user_profiles WHERE uid = 'u1'`;
  assert.equal(p.active_workspace_id, workspaceId);
});

test("member roles: owner only; the last owner cannot be demoted or removed", { skip: skipReason }, async () => {
  await rejectsWith(
    tx((t) => updateWorkspaceMemberRoleForUser(t, { ownerUid: "admin1", workspaceId: "ws_1", targetUserId: "u1", role: "member" })),
    "permission-denied",
    "Only owner can manage members",
  );
  await rejectsWith(
    tx((t) => updateWorkspaceMemberRoleForUser(t, { ownerUid: "u1", workspaceId: "ws_1", targetUserId: "admin1", role: "boss" })),
    "invalid-argument",
    "Unsupported workspace role",
  );
  await rejectsWith(
    tx((t) => updateWorkspaceMemberRoleForUser(t, { ownerUid: "u1", workspaceId: "ws_1", targetUserId: "u1", role: "admin" })),
    "failed-precondition",
    "Workspace must keep at least one owner",
  );
  const updated = await tx((t) =>
    updateWorkspaceMemberRoleForUser(t, { ownerUid: "u1", workspaceId: "ws_1", targetUserId: "admin1", role: "accountingApproved" }),
  );
  assert.deepEqual(updated, { userId: "admin1", workspaceId: "ws_1", role: "accountingApproved" });

  await rejectsWith(
    tx((t) => removeWorkspaceMemberForUser(t, { ownerUid: "u1", workspaceId: "ws_1", targetUserId: "u1" })),
    "failed-precondition",
    "Workspace must keep at least one owner",
  );
  const removed = await tx((t) => removeWorkspaceMemberForUser(t, { ownerUid: "u1", workspaceId: "ws_1", targetUserId: "admin1" }));
  assert.deepEqual(removed, { userId: "admin1", workspaceId: "ws_1", removed: true });
  await rejectsWith(
    tx((t) => removeWorkspaceMemberForUser(t, { ownerUid: "u1", workspaceId: "ws_1", targetUserId: "admin1" })),
    "not-found",
    "Workspace member not found",
  );
});

test("inviteMemberByEmail: unknown or existing → INVITE_UNAVAILABLE; team limit on free; notification", { skip: skipReason }, async () => {
  const invite = (email: string) =>
    tx((t) => inviteMemberByEmailForUser(t, { ownerUid: "u1", workspaceId: "ws_1", email, role: "member" }));
  await rejectsWith(invite("nobody@example.com"), "not-found", "INVITE_UNAVAILABLE");
  await rejectsWith(invite("A@Example.com"), "not-found", "INVITE_UNAVAILABLE");
  await assert.rejects(invite("friend@example.com"), (error: { message?: string; details?: unknown }) => {
    assert.equal(error.message, "LIMIT_REACHED");
    assert.deepEqual(error.details, { code: "LIMIT_REACHED", limitType: "teamMembers", current: 2, max: 1 });
    return true;
  });
  await pro();
  const result = await invite(" Friend@Example.com ");
  assert.deepEqual(result, { userId: "friend", workspaceId: "ws_1" });
  const [m] = await sql`SELECT id, role, invited_by FROM memberships WHERE workspace_id = 'ws_1' AND user_uid = 'friend'`;
  assert.deepEqual({ ...m }, { id: "ws_1_friend", role: "member", invited_by: "u1" });
  const [n] = await sql`SELECT id, target_user_id, type, title FROM notifications`;
  assert.deepEqual({ ...n }, {
    id: "team_invite_added_workspace_friend",
    target_user_id: "friend",
    type: "team_invite_added",
    title: "Workspace Access Granted",
  });
});

test("inviteMemberWithQuota: already a member → already-exists", { skip: skipReason }, async () => {
  await pro();
  await rejectsWith(
    tx((t) => inviteMemberWithQuotaForUser(t, { ownerUid: "u1", workspaceId: "ws_1", userId: "admin1" })),
    "already-exists",
    "User is already a member of this workspace",
  );
  const result = await tx((t) => inviteMemberWithQuotaForUser(t, { ownerUid: "u1", workspaceId: "ws_1", userId: "friend", role: "entryOnly" }));
  assert.deepEqual(result, { userId: "friend", workspaceId: "ws_1" });
});

test("checkLimit: usage against the plan; Pro is unlimited", { skip: skipReason }, async () => {
  await sql`INSERT INTO usage_counters (id, workspace_id, period, expenses_count)
            VALUES (${`ws_1_${periodKey()}`}, 'ws_1', ${periodKey()}, 29)`;
  const one = await checkLimitForUser(sql, "u1", { workspaceId: "ws_1", type: "expensesPerMonth" });
  assert.equal(one.allowed, true);
  assert.equal(one.current, 29);
  assert.equal(one.max, 30);
  assert.match(one.resetAt, /^\d{4}-\d{2}-01T00:00:00.000Z$/);
  const two = await checkLimitForUser(sql, "u1", { workspaceId: "ws_1", type: "expensesPerMonth", delta: 2 });
  assert.equal(two.allowed, false);
  const team = await checkLimitForUser(sql, "u1", { workspaceId: "ws_1", type: "teamMembers" });
  assert.deepEqual([team.current, team.max], [2, 1]);
  await rejectsWith(checkLimitForUser(sql, "u1", { workspaceId: "ws_1", type: "rockets" }), "invalid-argument", "Unsupported limit type");
  await pro();
  const unlimited = await checkLimitForUser(sql, "u1", { workspaceId: "ws_1", type: "teamMembers" });
  assert.deepEqual([unlimited.allowed, unlimited.current, unlimited.max], [true, 0, 999999]);
});
