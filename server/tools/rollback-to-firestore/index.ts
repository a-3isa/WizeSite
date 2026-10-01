/**
 * Rollback: copy what changed on the VPS since cutover back to Firebase (tasks.md T099, FR-016).
 *
 *   npm run rollback:firestore -- --since=<cutover_at ISO> [--dry-run] [--skip-files]
 *
 * Env: DATABASE_URL, GOOGLE_APPLICATION_CREDENTIALS (a key that can WRITE Firestore and Storage;
 *      the migration key is read-only), FIREBASE_PROJECT_ID (default wize-site),
 *      FIREBASE_STORAGE_BUCKET (default <project>.firebasestorage.app), FILES_ROOT.
 *
 * Order: deletions (tombstones, unless the row exists again) -> rows with updated_at > since
 * (whole-document set, see reverse.ts) -> one touch per affected project so the redeployed
 * Cloud Functions recompute the derived documents -> files modified since, uploaded to the same
 * path (MD5 checked by the client library). Derived tables are never written.
 * Run it with the Firestore rules still read-only and the app builds pointed back at Firebase.
 */
import { readdir, stat } from "node:fs/promises";
import path from "node:path";

import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import { createPool, type Sql } from "../../src/db/pool";
import { docIdColumn, rowToFirestoreDoc, TABLE_COLLECTIONS, type FirestoreWrite } from "./reverse";

function arg(name: string): string | undefined {
  const hit = process.argv.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  if (!hit) return undefined;
  return hit.includes("=") ? hit.slice(hit.indexOf("=") + 1) : "true";
}

const BATCH = 400;

async function commitInBatches(db: Firestore, ops: Array<(b: FirebaseFirestore.WriteBatch) => void>): Promise<void> {
  for (let i = 0; i < ops.length; i += BATCH) {
    const batch = db.batch();
    ops.slice(i, i + BATCH).forEach((op) => op(batch));
    await batch.commit();
  }
}

async function* filesChangedSince(root: string, since: Date, dir = root): AsyncGenerator<string> {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* filesChangedSince(root, since, full);
    } else if (entry.isFile() && (await stat(full)).mtime > since) {
      yield path.relative(root, full).split(path.sep).join("/");
    }
  }
}

export interface RollbackSummary {
  deleted: number;
  written: Record<string, number>;
  projectsTouched: number;
  files: number;
}

export async function rollback(
  sql: Sql,
  db: Firestore | null,
  since: Date,
): Promise<{ summary: RollbackSummary; deletes: Array<{ collection: string; id: string }>; writes: FirestoreWrite[]; projects: Set<string> }> {
  const deletes: Array<{ collection: string; id: string }> = [];
  const tombstones = await sql<{ table_name: string; row_id: string }[]>`
    SELECT DISTINCT table_name, row_id FROM deleted_rows WHERE deleted_at > ${since}`;
  for (const t of tombstones) {
    const collection = TABLE_COLLECTIONS[t.table_name];
    if (!collection) continue;
    const column = docIdColumn(t.table_name);
    const back = await sql`SELECT 1 FROM ${sql(t.table_name)} WHERE ${sql(column)} = ${t.row_id}`;
    if (back.length === 0) deletes.push({ collection, id: t.row_id });
  }

  const writes: FirestoreWrite[] = [];
  const written: Record<string, number> = {};
  const projects = new Set<string>();
  for (const table of Object.keys(TABLE_COLLECTIONS)) {
    const rows = await sql<Record<string, unknown>[]>`
      SELECT * FROM ${sql(table)} WHERE updated_at > ${since}`;
    for (const row of rows) {
      writes.push(rowToFirestoreDoc(table, row));
      if (typeof row.project_id === "string") projects.add(row.project_id);
      if (table === "projects") projects.add(`${row.id}`);
    }
    if (rows.length > 0) written[TABLE_COLLECTIONS[table]] = rows.length;
  }
  // A project deleted after cutover has nothing left to recompute.
  for (const d of deletes) if (d.collection === "projects") projects.delete(d.id);

  if (db) {
    await commitInBatches(db, deletes.map((d) => (b) => b.delete(db.collection(d.collection).doc(d.id))));
    await commitInBatches(db, writes.map((w) => (b) => b.set(db.collection(w.collection).doc(w.id), w.data)));
    await commitInBatches(
      db,
      [...projects].map((id) => (b) => b.set(db.collection("projects").doc(id), { updatedAt: FieldValue.serverTimestamp() }, { merge: true })),
    );
  }
  return {
    summary: { deleted: deletes.length, written, projectsTouched: projects.size, files: 0 },
    deletes,
    writes,
    projects,
  };
}

async function main(): Promise<void> {
  const sinceArg = arg("since");
  const since = sinceArg ? new Date(sinceArg) : undefined;
  if (!since || Number.isNaN(since.getTime())) throw new Error("--since=<ISO timestamp> is required (the recorded cutover_at)");
  const dryRun = arg("dry-run") === "true";
  const skipFiles = arg("skip-files") === "true";
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) throw new Error("DATABASE_URL is required");
  const filesRoot = process.env.FILES_ROOT;
  if (!skipFiles && !filesRoot) throw new Error("FILES_ROOT is required (or --skip-files)");
  const projectId = process.env.FIREBASE_PROJECT_ID ?? "wize-site";

  const app =
    getApps()[0] ??
    initializeApp({ projectId, storageBucket: process.env.FIREBASE_STORAGE_BUCKET ?? `${projectId}.firebasestorage.app` });
  const sql = createPool(databaseUrl, { max: 2 });
  try {
    const { summary } = await rollback(sql, dryRun ? null : getFirestore(app), since);
    if (!skipFiles && filesRoot) {
      const bucket = getStorage(app).bucket();
      for await (const storagePath of filesChangedSince(filesRoot, since)) {
        if (!dryRun) {
          await bucket.upload(path.join(filesRoot, storagePath), { destination: storagePath, validation: "md5" });
        }
        summary.files++;
      }
    }
    console.log(JSON.stringify({ since: since.toISOString(), dryRun, ...summary }, null, 2));
  } finally {
    await sql.end();
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
