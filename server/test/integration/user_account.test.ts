/** T062: updateUserProfile, updateUserSettings, deleteOwnAccount ported from functions/src/index.ts. */
import assert from "node:assert/strict";
import { access, mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { withTransaction } from "../../src/db/tx";
import { type AuthAdmin, deleteOwnAccountForUser, updateUserProfileForUser, updateUserSettingsForUser } from "../../src/rpc/user";
import { resetDatabase, seedWorkspace, skipReason, testSql } from "./helpers";

let sql: Sql;
let calls: string[];
let failDelete: boolean;
const admin: AuthAdmin = {
  async updateUser(uid, props) {
    calls.push(`update:${uid}:${props.displayName}:${props.photoURL ?? "-"}`);
  },
  async deleteUser(uid) {
    if (failDelete) throw new Error("auth down");
    calls.push(`delete:${uid}`);
  },
};

before(() => {
  if (!skipReason) sql = testSql();
});
after(async () => {
  if (sql) await sql.end();
});
beforeEach(async () => {
  calls = [];
  failDelete = false;
  if (!skipReason) {
    await resetDatabase(sql);
    await seedWorkspace(sql, { workspaceId: "ws_own", ownerUid: "u1" });
    await seedWorkspace(sql, { workspaceId: "ws_other", ownerUid: "boss", members: { u1: "member" } });
    await sql`INSERT INTO user_profiles (uid, email, full_name, default_currency, risk_alerts_enabled)
              VALUES ('u1', 'u1@example.com', 'Old', 'EGP', true), ('boss', 'b@example.com', 'Boss', 'EGP', true)`;
    await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('p_own', 'ws_own', 'Mine'), ('p_other', 'ws_other', 'Theirs')`;
  }
});

const tx = <T>(fn: (t: Sql) => Promise<T>) => withTransaction(sql, fn);
const now = () => Math.floor(Date.now() / 1000);
async function rejectsWith(promise: Promise<unknown>, code: string, message: string) {
  await assert.rejects(promise, (error: { code?: string; message?: string }) => {
    assert.equal(error.code, code);
    assert.equal(error.message, message);
    return true;
  });
}

test("updateUserProfile: Firebase display name + profile row; bad currency falls back to EGP", { skip: skipReason }, async () => {
  await tx((t) => updateUserProfileForUser(t, admin, "u1", { fullName: " سارة ", photoUrl: "", defaultCurrency: "xyz", riskAlertsEnabled: false }));
  assert.deepEqual(calls, ["update:u1:سارة:-"]);
  const [p] = await sql`SELECT full_name, photo_url, default_currency, risk_alerts_enabled FROM user_profiles WHERE uid = 'u1'`;
  assert.deepEqual({ ...p }, { full_name: "سارة", photo_url: "", default_currency: "EGP", risk_alerts_enabled: false });
  await rejectsWith(tx((t) => updateUserProfileForUser(t, admin, "u1", { fullName: " " })), "invalid-argument", "Missing required field: fullName");
});

test("updateUserSettings: own settings only; unset fields untouched", { skip: skipReason }, async () => {
  await rejectsWith(
    tx((t) => updateUserSettingsForUser(t, "u1", { userId: "boss", defaultCurrency: "SAR" })),
    "permission-denied",
    "Cannot update another user's settings",
  );
  await tx((t) => updateUserSettingsForUser(t, "u1", { defaultCurrency: "sar" }));
  const [p] = await sql`SELECT default_currency, risk_alerts_enabled FROM user_profiles WHERE uid = 'u1'`;
  assert.deepEqual({ ...p }, { default_currency: "SAR", risk_alerts_enabled: true });
});

test("deleteOwnAccount: needs a recent sign-in; blocked while an owned workspace has other members", { skip: skipReason }, async () => {
  const files = { root: "/nonexistent" };
  await rejectsWith(
    tx((t) => deleteOwnAccountForUser(t, admin, files, { uid: "u1", authTime: now() - 3600 })),
    "failed-precondition",
    "RECENT_LOGIN_REQUIRED",
  );
  await sql`INSERT INTO memberships (id, workspace_id, user_uid, role) VALUES ('ws_own_friend', 'ws_own', 'friend', 'member')`;
  await rejectsWith(
    tx((t) => deleteOwnAccountForUser(t, admin, files, { uid: "u1", authTime: now() })),
    "failed-precondition",
    "TRANSFER_OWNERSHIP_REQUIRED",
  );
  assert.deepEqual(calls, []);
});

test("deleteOwnAccount: owned workspaces, memberships, profile and files removed; Firebase user deleted", { skip: skipReason }, async () => {
  const root = await mkdtemp(path.join(tmpdir(), "del-"));
  await mkdir(path.join(root, "receipts/u1"), { recursive: true });
  await writeFile(path.join(root, "receipts/u1/r.jpg"), "x");
  await mkdir(path.join(root, "receipts/boss"), { recursive: true });
  await writeFile(path.join(root, "receipts/boss/keep.jpg"), "x");

  const result = await tx((t) => deleteOwnAccountForUser(t, admin, { root }, { uid: "u1", authTime: now() }));
  assert.deepEqual(result, { deleted: true });
  assert.deepEqual(calls, ["delete:u1"]);
  const [left] = await sql`SELECT
      (SELECT count(*)::int FROM workspaces WHERE id = 'ws_own') AS own,
      (SELECT count(*)::int FROM projects WHERE id = 'p_own') AS own_projects,
      (SELECT count(*)::int FROM memberships WHERE user_uid = 'u1') AS memberships,
      (SELECT count(*)::int FROM user_profiles WHERE uid = 'u1') AS profile,
      (SELECT count(*)::int FROM projects WHERE id = 'p_other') AS other_projects`;
  assert.deepEqual({ ...left }, { own: 0, own_projects: 0, memberships: 0, profile: 0, other_projects: 1 });
  await assert.rejects(access(path.join(root, "receipts/u1/r.jpg")));
  await access(path.join(root, "receipts/boss/keep.jpg"));
});

test("deleteOwnAccount: if Firebase refuses, nothing is deleted", { skip: skipReason }, async () => {
  failDelete = true;
  await assert.rejects(tx((t) => deleteOwnAccountForUser(t, admin, { root: "/nonexistent" }, { uid: "u1", authTime: now() })));
  const [p] = await sql`SELECT count(*)::int AS n FROM user_profiles WHERE uid = 'u1'`;
  assert.equal(p.n, 1);
});
