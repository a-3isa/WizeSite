import type { Sql } from "../db/pool";

/**
 * upsertNotificationForUsers: one notification per (type, project or "workspace", user), merged
 * on repeat (title, message and workspace refreshed; read state kept), as the Firestore doc was.
 */
export async function upsertNotificationForUsers(
  sql: Sql,
  input: { workspaceId: string; userIds: string[]; type: string; title: string; message: string; projectId?: string },
): Promise<void> {
  for (const userId of input.userIds) {
    const id = [input.type, input.projectId ?? "workspace", userId].join("_");
    await sql`
      INSERT INTO notifications (id, workspace_id, target_user_id, type, title, message, legacy)
      VALUES (${id}, ${input.workspaceId}, ${userId}, ${input.type}, ${input.title}, ${input.message},
              ${sql.json({ projectId: input.projectId ?? null } as never)})
      ON CONFLICT (id) DO UPDATE SET
        workspace_id = EXCLUDED.workspace_id, target_user_id = EXCLUDED.target_user_id, type = EXCLUDED.type,
        title = EXCLUDED.title, message = EXCLUDED.message, legacy = notifications.legacy || EXCLUDED.legacy,
        created_at = now(), updated_at = now()`;
  }
}
