/**
 * Reads the source data from Firebase (tasks.md T035). Read-only against Firestore and Auth.
 * Also writes an audit snapshot (NDJSON per collection) so a run can be inspected afterwards.
 */
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

import type { Auth } from "firebase-admin/auth";
import { Timestamp, type Firestore } from "firebase-admin/firestore";

import type { ExportedCollections } from "./transform";

export async function exportCollections(
  db: Firestore,
  collections: string[],
): Promise<ExportedCollections> {
  const out: ExportedCollections = {};
  for (const name of collections) {
    const snap = await db.collection(name).get();
    out[name] = snap.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
  }
  return out;
}

/** Every uid that still exists in Firebase Auth (FR-014: data of deleted accounts is not migrated). */
export async function listLiveUids(auth: Auth): Promise<Set<string>> {
  const uids = new Set<string>();
  let pageToken: string | undefined;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) uids.add(user.uid);
    pageToken = page.pageToken;
  } while (pageToken);
  return uids;
}

/** NDJSON with Timestamps encoded as {"__timestamp": [seconds, nanoseconds]} so nothing is lost. */
export async function writeSnapshot(dir: string, exported: ExportedCollections): Promise<void> {
  await mkdir(dir, { recursive: true });
  const replacer = (_key: string, value: unknown) =>
    value instanceof Timestamp ? { __timestamp: [value.seconds, value.nanoseconds] } : value;
  for (const [collection, docs] of Object.entries(exported)) {
    const lines = docs.map((doc) => JSON.stringify(doc, replacer)).join("\n");
    await writeFile(path.join(dir, `${collection}.ndjson`), lines ? `${lines}\n` : "", "utf8");
  }
}
