/**
 * Postgres row → Firestore document, the reverse of tools/migrate-from-firestore/transform.ts
 * (data-model.md "Reverse mapping (rollback)", tasks.md T099). Pure.
 *
 * Builds on rowToDoc (snake_case → camelCase, NUMERIC → number, NULL → absent, `legacy` keys first
 * so mapped columns win) and undoes what the forward transform added: the renamed columns, the
 * document id copied into a column, `usage_counters.period`, and the `payload` wrapper.
 * Timestamps stay Dates; the Admin SDK stores them as Firestore Timestamps.
 */
import { rowToDoc } from "../../src/recompute/rows";
import { COLLECTION_TABLES } from "../migrate-from-firestore/transform";

/** Base tables written back, table → Firestore collection. webhook_events is a server-side log. */
export const TABLE_COLLECTIONS: Record<string, string> = Object.fromEntries(
  Object.entries(COLLECTION_TABLES)
    .filter(([, table]) => table !== "webhook_events")
    .map(([collection, table]) => [table, collection]),
);

/** The column holding the Firestore document id. */
export function docIdColumn(table: string): string {
  if (table === "user_profiles") return "uid";
  if (table === "subscriptions") return "workspace_id";
  return "id";
}

/** Inverse of the forward RENAMES. */
const FIELD_RENAMES: Record<string, Record<string, string>> = {
  user_profiles: { activeWorkspaceId: "workspaceId" },
  workspaces: { ownerUid: "ownerId" },
  memberships: { userUid: "userId" },
};

/** Columns the forward transform derived; they were never Firestore fields. */
const DERIVED_FIELDS: Record<string, string[]> = {
  usage_counters: ["period"],
};

const PAYLOAD_TABLES = new Set(["drafts", "reports", "report_exports"]);

export interface FirestoreWrite {
  collection: string;
  id: string;
  data: Record<string, unknown>;
}

export function rowToFirestoreDoc(table: string, row: Record<string, unknown>): FirestoreWrite {
  const collection = TABLE_COLLECTIONS[table];
  if (!collection) throw new Error(`No Firestore collection for table ${table}`);
  const id = `${row[docIdColumn(table)]}`;

  if (PAYLOAD_TABLES.has(table)) {
    const payload =
      row.payload && typeof row.payload === "object" ? (row.payload as Record<string, unknown>) : {};
    const data: Record<string, unknown> = { ...payload };
    if (row.workspace_id != null) data.workspaceId = row.workspace_id;
    if (row.uid != null) data.uid = row.uid;
    if (row.created_at != null) data.createdAt = row.created_at;
    if (row.updated_at != null) data.updatedAt = row.updated_at;
    return { collection, id, data };
  }

  const doc = rowToDoc(row) as Record<string, unknown>;
  const data: Record<string, unknown> = {};
  const renames = FIELD_RENAMES[table] ?? {};
  for (const [field, value] of Object.entries(doc)) {
    data[renames[field] ?? field] = value;
  }
  if (table !== "user_profiles" && table !== "subscriptions") delete data.id;
  for (const field of DERIVED_FIELDS[table] ?? []) delete data[field];
  return { collection, id, data };
}
