/**
 * Firestore documents → Postgres rows (tasks.md T036, data-model.md "Migration mapping").
 *
 * Pure: takes the exported documents, the live table columns (read from information_schema by
 * the loader, so the migrations stay the single source of truth) and the set of uids that still
 * exist in Firebase Auth. Returns rows per table, fields that would lose money precision, and
 * skip counts. Nothing is silently dropped: unmapped fields go to `legacy`.
 */
import { FLOAT_COLUMNS, NUMERIC_COLUMNS } from "../../src/recompute/rows";

export interface ExportedDoc {
  id: string;
  data: Record<string, unknown>;
}
export type ExportedCollections = Record<string, ExportedDoc[]>;
export type TableColumns = Map<string, Set<string>>;
export type Row = Record<string, unknown>;

export interface PrecisionFlag {
  table: string;
  id: string;
  column: string;
  value: number;
}

/** Several membership docs for one (workspace, user); Postgres allows exactly one. */
export interface DuplicateMembership {
  workspaceId: string;
  userId: string;
  /** Doc kept: the canonical `${workspaceId}_${userId}` id when present, else the newest. */
  kept: string;
  dropped: string[];
  /** The docs disagree on role or status: a human must decide, so the load is blocked. */
  conflicting: boolean;
}

export interface TransformResult {
  rows: Map<string, Row[]>;
  precisionFlags: PrecisionFlag[];
  /**
   * Source collection → documents not loaded: owner account no longer exists, or a merged
   * duplicate membership (see [duplicates]).
   */
  skipped: Map<string, number>;
  duplicates: DuplicateMembership[];
  /**
   * Rows that would violate a (workspace_id, client_mutation_id) unique key. A human must decide
   * which record is real, so these block the load.
   */
  uniqueConflicts: string[];
}

/** Firestore collection → table. Collections not listed here are not migrated. */
export const COLLECTION_TABLES: Record<string, string> = {
  users: "user_profiles",
  workspaces: "workspaces",
  memberships: "memberships",
  subscriptions: "subscriptions",
  usage_counters: "usage_counters",
  webhook_events: "webhook_events",
  projects: "projects",
  workers: "workers",
  entities: "entities",
  expenses: "expenses",
  payments: "payments",
  worker_entries: "worker_entries",
  worker_accounting_records: "worker_accounting_records",
  contractor_accounting_records: "contractor_accounting_records",
  equipment_accounting_records: "equipment_accounting_records",
  transport_provider_accounting_records: "transport_provider_accounting_records",
  attachments: "attachments",
  notifications: "notifications",
  drafts: "drafts",
  reports: "reports",
  report_exports: "report_exports",
};
// Not migrated on purpose: idempotency_keys (old keys are meaningless after cutover; the queue is
// empty), and every derived collection (project_metrics, *_summaries, workspace_metrics): those are
// recomputed from base rows and only compared in the verification report.

/** Field → column renames that camelCase→snake_case alone does not produce. */
const RENAMES: Record<string, Record<string, string>> = {
  user_profiles: { workspaceId: "active_workspace_id" },
  workspaces: { ownerId: "owner_uid" },
  memberships: { userId: "user_uid" },
};

/** Tables whose whole document is kept as `payload` (their shape is not modelled as columns). */
const PAYLOAD_TABLES = new Set(["drafts", "reports", "report_exports"]);

function snake(field: string): string {
  return field.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
}

function isTimestamp(value: unknown): value is { toDate(): Date; seconds: number; nanoseconds: number } {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { toDate?: unknown }).toDate === "function" &&
    typeof (value as { seconds?: unknown }).seconds === "number"
  );
}

function toDate(value: { seconds: number; nanoseconds: number }): Date {
  // JS Dates hold milliseconds; timestamptz holds microseconds. Firestore values written by the app
  // carry at most millisecond precision, so this is exact for real data.
  return new Date(value.seconds * 1000 + Math.floor(value.nanoseconds / 1_000_000));
}

/** Converts Timestamps anywhere inside a JSON value to ISO strings (jsonb columns). */
function jsonSafe(value: unknown): unknown {
  if (isTimestamp(value)) return toDate(value).toISOString();
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(jsonSafe);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, jsonSafe(v)]));
  }
  return value;
}

/** Money: exact 2-decimal string when the double is a clean cent value, raw string (flagged) otherwise. */
function money(
  value: unknown,
  flag: (value: number) => void,
): string | null {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return String(value);
  const cents = Math.round(n * 100);
  if (Math.abs(cents / 100 - n) < 1e-9) {
    return (cents / 100).toFixed(2);
  }
  flag(n);
  return String(n);
}

function toRow(
  table: string,
  doc: ExportedDoc,
  cols: Set<string>,
  flags: PrecisionFlag[],
): Row {
  const row: Row = {};
  const legacy: Record<string, unknown> = {};
  const renames = RENAMES[table] ?? {};

  if (PAYLOAD_TABLES.has(table)) {
    const { workspaceId, uid, createdAt, updatedAt, id: _id, ...rest } = doc.data;
    row.id = doc.id;
    if (cols.has("workspace_id") && workspaceId) row.workspace_id = workspaceId;
    if (cols.has("uid") && uid) row.uid = uid;
    if (isTimestamp(createdAt)) row.created_at = toDate(createdAt);
    if (isTimestamp(updatedAt)) row.updated_at = toDate(updatedAt);
    row.payload = jsonSafe(rest);
    return row;
  }

  for (const [field, value] of Object.entries(doc.data)) {
    if (field === "id") continue; // the document id is authoritative
    const column = renames[field] ?? snake(field);
    if (!cols.has(column) || column === "legacy") {
      legacy[field] = jsonSafe(value);
      continue;
    }
    if (column === "client_mutation_id" && (value === "" || value === null)) {
      // Blank means "none"; NULL keeps the (workspace_id, client_mutation_id) key satisfiable.
      row[column] = null;
    } else if (FLOAT_COLUMNS.has(column)) {
      const n = value === null || value === undefined || value === "" ? null : Number(value);
      row[column] = n !== null && Number.isFinite(n) ? n : null;
    } else if (NUMERIC_COLUMNS.has(column)) {
      row[column] = money(value, (n) => flags.push({ table, id: doc.id, column, value: n }));
    } else if (isTimestamp(value)) {
      row[column] = toDate(value);
    } else if (value !== null && typeof value === "object") {
      row[column] = jsonSafe(value);
    } else {
      row[column] = value;
    }
  }

  // Document identity.
  if (table === "user_profiles") row.uid = doc.id;
  else if (table === "subscriptions") row.workspace_id = doc.id;
  else row.id = doc.id;

  if (table === "memberships" && cols.has("status") && row.status == null) {
    row.status = "active"; // existence = membership (firestore.rules hasMembership)
  }
  if (table === "usage_counters") {
    const ws = `${row.workspace_id ?? ""}`;
    row.period = ws && doc.id.startsWith(`${ws}_`) ? doc.id.slice(ws.length + 1) : doc.id;
  }
  if (cols.has("legacy")) row.legacy = legacy;
  return row;
}

function ownerOf(table: string, row: Row): { uid?: string; workspaceId?: string } {
  switch (table) {
    case "user_profiles":
      return { uid: `${row.uid}` };
    case "memberships":
      return { uid: `${row.user_uid ?? ""}`, workspaceId: `${row.workspace_id ?? ""}` };
    case "workspaces":
      return { workspaceId: `${row.id}` };
    default:
      return { workspaceId: row.workspace_id == null ? undefined : `${row.workspace_id}` };
  }
}

export function transformExport(
  exported: ExportedCollections,
  columns: TableColumns,
  liveUids: Set<string>,
): TransformResult {
  const rows = new Map<string, Row[]>();
  const precisionFlags: PrecisionFlag[] = [];
  const skipped = new Map<string, number>();

  // Workspaces whose owner account was deleted are dropped with everything scoped to them.
  const deadWorkspaces = new Set(
    (exported.workspaces ?? [])
      .filter((w) => !liveUids.has(`${w.data.ownerId ?? ""}`))
      .map((w) => w.id),
  );

  for (const [collection, docs] of Object.entries(exported)) {
    const table = COLLECTION_TABLES[collection];
    if (!table) continue;
    const cols = columns.get(table);
    if (!cols) throw new Error(`Table ${table} missing from the target schema`);
    const out: Row[] = [];
    for (const doc of docs) {
      const row = toRow(table, doc, cols, precisionFlags);
      const owner = ownerOf(table, row);
      const deadUser = owner.uid !== undefined && !liveUids.has(owner.uid);
      const deadWorkspace = owner.workspaceId !== undefined && deadWorkspaces.has(owner.workspaceId);
      if (deadUser || deadWorkspace) {
        skipped.set(collection, (skipped.get(collection) ?? 0) + 1);
        continue;
      }
      out.push(row);
    }
    rows.set(table, out);
  }
  const duplicates = dedupeMemberships(rows, skipped);
  return { rows, precisionFlags, skipped, duplicates, uniqueConflicts: findMutationIdConflicts(rows) };
}

function findMutationIdConflicts(rows: Map<string, Row[]>): string[] {
  const conflicts: string[] = [];
  for (const [table, list] of rows) {
    const byKey = new Map<string, string[]>();
    for (const row of list) {
      const mutationId = row.client_mutation_id;
      if (typeof mutationId !== "string" || mutationId === "") continue;
      const key = `${row.workspace_id ?? ""}|${mutationId}`;
      byKey.set(key, [...(byKey.get(key) ?? []), `${row.id}`]);
    }
    for (const [key, ids] of byKey) {
      if (ids.length < 2) continue;
      const [workspaceId, mutationId] = key.split("|");
      conflicts.push(`${table}: client_mutation_id ${mutationId} repeated in workspace ${workspaceId} (${ids.join(", ")})`);
    }
  }
  return conflicts;
}

function timeOf(value: unknown): number {
  if (value instanceof Date) return value.getTime();
  return 0;
}

/**
 * Legacy clients created owner memberships under random ids before the canonical
 * `${workspaceId}_${userId}` id existed, so one pair can have two docs. Keep one row per pair.
 */
function dedupeMemberships(rows: Map<string, Row[]>, skipped: Map<string, number>): DuplicateMembership[] {
  const memberships = rows.get("memberships");
  if (!memberships) return [];
  const groups = new Map<string, Row[]>();
  for (const row of memberships) {
    const key = `${row.workspace_id ?? ""}|${row.user_uid ?? ""}`;
    groups.set(key, [...(groups.get(key) ?? []), row]);
  }
  const duplicates: DuplicateMembership[] = [];
  const keep: Row[] = [];
  for (const group of groups.values()) {
    if (group.length === 1) {
      keep.push(group[0]);
      continue;
    }
    const workspaceId = `${group[0].workspace_id ?? ""}`;
    const userId = `${group[0].user_uid ?? ""}`;
    const canonical = group.find((r) => r.id === `${workspaceId}_${userId}`);
    const kept =
      canonical ??
      [...group].sort(
        (a, b) => timeOf(b.updated_at ?? b.created_at) - timeOf(a.updated_at ?? a.created_at),
      )[0];
    const signature = (r: Row) => `${r.role ?? ""}|${r.status ?? ""}`;
    duplicates.push({
      workspaceId,
      userId,
      kept: `${kept.id}`,
      dropped: group.filter((r) => r !== kept).map((r) => `${r.id}`),
      conflicting: new Set(group.map(signature)).size > 1,
    });
    keep.push(kept);
    skipped.set("memberships", (skipped.get("memberships") ?? 0) + group.length - 1);
  }
  rows.set("memberships", keep);
  return duplicates;
}
