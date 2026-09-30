import { rm } from "node:fs/promises";
import path from "node:path";

import type { Sql } from "../db/pool";
import { isRecentLogin, ownerDeletionBlocked, userStoragePrefixes } from "../domain/account_deletion";
import { RpcError } from "../domain/errors";
import { legacyFields, mutationIdOf } from "./records";
import type { RpcContext, RpcRegistry } from "./types";
import { asRecord, requireString } from "./validation";

/**
 * User account RPCs ported from functions/src/index.ts (updateUserProfile, updateUserSettings,
 * deleteOwnAccount). The Firebase sign-in account is changed through [AuthAdmin], which needs a
 * service account allowed to administer Firebase Authentication.
 */
export interface AuthAdmin {
  updateUser(uid: string, props: { displayName: string; photoURL?: string }): Promise<void>;
  deleteUser(uid: string): Promise<void>;
}

/** Used when no admin credential is configured: fail clearly instead of half-running. */
export const unavailableAuthAdmin: AuthAdmin = {
  async updateUser() {
    throw new RpcError("unavailable", "Account changes are not available right now.");
  },
  async deleteUser() {
    throw new RpcError("unavailable", "Account changes are not available right now.");
  },
};

const SUPPORTED_CURRENCIES = ["EGP", "USD", "SAR", "AED", "KWD", "QAR", "BHD", "OMR", "JOD"];

/** currencyCode: unsupported values fall back to EGP. */
function currencyCode(input: unknown): string {
  const raw = `${input ?? "EGP"}`.trim().toUpperCase();
  return SUPPORTED_CURRENCIES.includes(raw) ? raw : "EGP";
}

function asBooleanOrUndefined(input: unknown): boolean | undefined {
  return typeof input === "boolean" ? input : undefined;
}

export async function updateUserProfileForUser(
  sql: Sql,
  admin: AuthAdmin,
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const fullName = requireString(data, "fullName");
  const photoUrl = `${data.photoUrl ?? ""}`.trim();
  const defaultCurrency = currencyCode(data.defaultCurrency);
  const riskAlertsEnabled = asBooleanOrUndefined(data.riskAlertsEnabled);
  await sql`
    INSERT INTO user_profiles (uid, full_name, photo_url, default_currency, risk_alerts_enabled)
    VALUES (${uid}, ${fullName}, ${photoUrl}, ${defaultCurrency}, ${riskAlertsEnabled ?? true})
    ON CONFLICT (uid) DO UPDATE SET
      full_name = EXCLUDED.full_name, photo_url = EXCLUDED.photo_url, default_currency = EXCLUDED.default_currency,
      risk_alerts_enabled = ${riskAlertsEnabled === undefined ? sql`user_profiles.risk_alerts_enabled` : sql`EXCLUDED.risk_alerts_enabled`},
      updated_at = now()`;
  // Last, so a Firebase failure rolls the profile change back with the transaction.
  await admin.updateUser(uid, { displayName: fullName, photoURL: photoUrl || undefined });
}

export async function updateUserSettingsForUser(sql: Sql, uid: string, data: Record<string, unknown>): Promise<void> {
  const targetUserId = `${data.userId ?? uid}`.trim();
  if (targetUserId !== uid) {
    throw new RpcError("permission-denied", "Cannot update another user's settings");
  }
  const riskAlertsEnabled = asBooleanOrUndefined(data.riskAlertsEnabled);
  await sql`
    INSERT INTO user_profiles (uid, default_currency, risk_alerts_enabled, legacy)
    VALUES (${uid}, ${currencyCode(data.defaultCurrency)}, ${riskAlertsEnabled ?? true},
            ${sql.json({ clientMutationId: mutationIdOf(data) ?? "", ...legacyFields({ clientUpdatedAt: data.clientUpdatedAt }) } as never)})
    ON CONFLICT (uid) DO UPDATE SET
      default_currency = EXCLUDED.default_currency,
      risk_alerts_enabled = ${riskAlertsEnabled === undefined ? sql`user_profiles.risk_alerts_enabled` : sql`EXCLUDED.risk_alerts_enabled`},
      legacy = user_profiles.legacy || EXCLUDED.legacy,
      updated_at = now()`;
}

/**
 * Port of deleteOwnAccount. Owned workspaces go with everything scoped to them (FK cascade), then
 * the user's memberships, idempotency keys and profile. Firebase's deleteUser runs before commit,
 * so if it fails nothing is deleted; the user's files are removed last, best effort.
 */
export async function deleteOwnAccountForUser(
  sql: Sql,
  admin: AuthAdmin,
  files: { root: string },
  caller: { uid: string; authTime?: number },
): Promise<{ deleted: boolean }> {
  if (!isRecentLogin(caller.authTime)) {
    throw new RpcError("failed-precondition", "RECENT_LOGIN_REQUIRED");
  }
  const uid = caller.uid;
  const owned = await sql<{ workspace_id: string; others: number }[]>`
    SELECT m.workspace_id,
           (SELECT count(*)::int FROM memberships o WHERE o.workspace_id = m.workspace_id AND o.user_uid <> ${uid}) AS others
    FROM memberships m
    WHERE m.user_uid = ${uid} AND m.role = 'owner' AND trim(m.workspace_id) <> ''`;
  for (const workspace of owned) {
    if (ownerDeletionBlocked(workspace.others)) {
      throw new RpcError("failed-precondition", "TRANSFER_OWNERSHIP_REQUIRED");
    }
  }
  const ownedIds = owned.map((w) => w.workspace_id);
  if (ownedIds.length > 0) {
    await sql`DELETE FROM workspaces WHERE id IN ${sql(ownedIds)}`;
  }
  await sql`DELETE FROM memberships WHERE user_uid = ${uid}`;
  await sql`DELETE FROM idempotency_keys WHERE uid = ${uid}`;
  await sql`DELETE FROM user_profiles WHERE uid = ${uid}`;
  await admin.deleteUser(uid);

  const root = path.resolve(files.root);
  for (const prefix of userStoragePrefixes(uid)) {
    const target = path.resolve(root, prefix);
    if (target.startsWith(root + path.sep)) {
      await rm(target, { recursive: true, force: true }).catch(() => undefined);
    }
  }
  return { deleted: true };
}

export function userRpcs(deps: { authAdmin: AuthAdmin; files: { root: string } }): RpcRegistry {
  return {
    updateUserProfile: {
      mutating: true,
      handler: async (ctx: RpcContext, data) => {
        await updateUserProfileForUser(ctx.sql, deps.authAdmin, ctx.uid, asRecord(data));
        return null;
      },
    },
    updateUserSettings: {
      mutating: true,
      handler: async (ctx, data) => {
        await updateUserSettingsForUser(ctx.sql, ctx.uid, asRecord(data));
        return null;
      },
    },
    deleteOwnAccount: {
      mutating: true,
      handler: (ctx) => deleteOwnAccountForUser(ctx.sql, deps.authAdmin, deps.files, { uid: ctx.uid, authTime: ctx.authTime }),
    },
  };
}
