import { roleForUser } from "../auth/roles";
import type { Sql } from "../db/pool";
import { RpcError } from "../domain/errors";
import type { RpcRegistry } from "./types";
import { asRecord, newDocId, nonEmptyStringOrUndefined, normalizeEmail, requireString } from "./validation";

/** Postgres port of userWorkspaceName (functions/src/index.ts). */
function userWorkspaceName(input: string): string {
  const trimmed = input.trim();
  return trimmed.length > 0 ? `${trimmed} Workspace` : "New Workspace";
}

async function ensureOwnerMembership(sql: Sql, workspaceId: string, uid: string): Promise<void> {
  await sql`
    INSERT INTO memberships (id, workspace_id, user_uid, role)
    VALUES (${`${workspaceId}_${uid}`}, ${workspaceId}, ${uid}, 'owner')
    ON CONFLICT (workspace_id, user_uid) DO NOTHING`;
}

/**
 * Port of bootstrapWorkspaceForUser. Resolution order is unchanged:
 * 1. any membership → that workspace; 2. legacy active workspace on the profile;
 * 3. otherwise create a workspace + owner membership + profile.
 * Existing profile values always win over values from the token.
 */
export async function bootstrapWorkspaceForUser(
  sql: Sql,
  input: { uid: string; email?: string | null; fullName?: string | null; photoUrl?: string | null },
): Promise<{ workspaceId: string; created: boolean; setupCompleted: boolean }> {
  const uid = input.uid.trim();
  if (!uid) {
    throw new RpcError("invalid-argument", "Missing authenticated user");
  }
  const incomingEmail = nonEmptyStringOrUndefined(normalizeEmail(`${input.email ?? ""}`));
  const incomingFullName = nonEmptyStringOrUndefined(`${input.fullName ?? ""}`);
  const incomingPhotoUrl = nonEmptyStringOrUndefined(`${input.photoUrl ?? ""}`);
  const fullName = incomingFullName ?? "";

  const [existing] = await sql<Array<{ setup_completed: boolean; active_workspace_id: string | null }>>`
    SELECT setup_completed, active_workspace_id FROM user_profiles WHERE uid = ${uid}`;
  const existingSetupCompleted = existing ? existing.setup_completed !== false : false;

  // Upsert the profile: keep existing values, fill blanks from the token, new users get defaults.
  const writeProfile = async (workspaceId: string) => {
    if (existing) {
      await sql`
        UPDATE user_profiles SET
          active_workspace_id = ${workspaceId},
          email = COALESCE(NULLIF(email, ''), ${incomingEmail ?? null}),
          full_name = COALESCE(NULLIF(full_name, ''), ${incomingFullName ?? null}),
          photo_url = COALESCE(NULLIF(photo_url, ''), ${incomingPhotoUrl ?? null}),
          updated_at = now()
        WHERE uid = ${uid}`;
    } else {
      await sql`
        INSERT INTO user_profiles
          (uid, email, full_name, photo_url, active_workspace_id, default_currency, risk_alerts_enabled, setup_completed)
        VALUES (${uid}, ${incomingEmail ?? null}, ${incomingFullName ?? null}, ${incomingPhotoUrl ?? null},
                ${workspaceId}, 'EGP', true, false)`;
    }
  };

  const [membership] = await sql<{ workspace_id: string }[]>`
    SELECT workspace_id FROM memberships WHERE user_uid = ${uid} ORDER BY created_at LIMIT 1`;
  if (membership?.workspace_id) {
    await writeProfile(membership.workspace_id);
    return { workspaceId: membership.workspace_id, created: false, setupCompleted: existingSetupCompleted };
  }

  const legacyWorkspaceId = `${existing?.active_workspace_id ?? ""}`.trim();
  if (legacyWorkspaceId) {
    const [legacy] = await sql<{ owner_uid: string }[]>`
      SELECT owner_uid FROM workspaces WHERE id = ${legacyWorkspaceId}`;
    if (!legacy) {
      await sql`INSERT INTO workspaces (id, owner_uid, name)
                VALUES (${legacyWorkspaceId}, ${uid}, ${userWorkspaceName(fullName)})`;
    }
    if (legacy && legacy.owner_uid !== uid) {
      if (!(await roleForUser(sql, legacyWorkspaceId, uid))) {
        throw new RpcError(
          "failed-precondition",
          "Legacy workspace points to a workspace owned by another user without a valid membership.",
        );
      }
    } else {
      await ensureOwnerMembership(sql, legacyWorkspaceId, uid);
    }
    await writeProfile(legacyWorkspaceId);
    return { workspaceId: legacyWorkspaceId, created: false, setupCompleted: existingSetupCompleted };
  }

  const workspaceId = newDocId();
  await sql`INSERT INTO workspaces (id, owner_uid, name)
            VALUES (${workspaceId}, ${uid}, ${userWorkspaceName(fullName)})`;
  await ensureOwnerMembership(sql, workspaceId, uid);
  await writeProfile(workspaceId);
  return { workspaceId, created: true, setupCompleted: false };
}

/** Port of setActiveWorkspaceForUser: members switch; an owner without a membership row is repaired. */
export async function setActiveWorkspaceForUser(
  sql: Sql,
  input: { uid: string; workspaceId: string },
): Promise<{ workspaceId: string }> {
  const uid = input.uid.trim();
  const workspaceId = input.workspaceId.trim();
  if (!uid || !workspaceId) {
    throw new RpcError("invalid-argument", "Missing workspace selection");
  }
  const role = await roleForUser(sql, workspaceId, uid);
  if (!role) {
    const [ws] = await sql<{ owner_uid: string }[]>`SELECT owner_uid FROM workspaces WHERE id = ${workspaceId}`;
    if (`${ws?.owner_uid ?? ""}` !== uid) {
      throw new RpcError("permission-denied", "User is not a member of this workspace");
    }
    await ensureOwnerMembership(sql, workspaceId, uid);
  }
  await sql`
    INSERT INTO user_profiles (uid, active_workspace_id) VALUES (${uid}, ${workspaceId})
    ON CONFLICT (uid) DO UPDATE SET active_workspace_id = EXCLUDED.active_workspace_id, updated_at = now()`;
  return { workspaceId };
}

export const workspaceRpcs: RpcRegistry = {
  ensureUserWorkspaceBootstrap: {
    mutating: true,
    handler: (ctx) =>
      bootstrapWorkspaceForUser(ctx.sql, {
        uid: ctx.uid,
        email: ctx.email,
        fullName: ctx.name,
        photoUrl: ctx.picture,
      }),
  },
  setActiveWorkspace: {
    mutating: true,
    handler: (ctx, data) =>
      setActiveWorkspaceForUser(ctx.sql, {
        uid: ctx.uid,
        workspaceId: requireString(asRecord(data), "workspaceId"),
      }),
  },
};
