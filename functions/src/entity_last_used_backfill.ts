import * as admin from "firebase-admin";

type EntityData = Record<string, unknown>;

export type EntityLastUsedBackfillPatch = {
  id?: string;
  normalizedName?: string;
  lastUsedAt?: Date;
};

export type EntityLastUsedBackfillResult = {
  scanned: number;
  updated: number;
  lastCursor: string | null;
};

function normalizeName(value: unknown): string {
  return `${value ?? ""}`.trim().toLowerCase().replace(/\s+/g, " ");
}

function parseDate(value: unknown): Date | null {
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === "object" && value !== null) {
    const candidate = value as { toDate?: () => Date };
    if (typeof candidate.toDate === "function") {
      const converted = candidate.toDate();
      return Number.isNaN(converted.getTime()) ? null : converted;
    }
  }
  return null;
}

export function buildEntityLastUsedAtBackfillPatch(
  entityId: string,
  data: EntityData,
): EntityLastUsedBackfillPatch | null {
  const patch: EntityLastUsedBackfillPatch = {};
  if (`${data.id ?? ""}` !== entityId) {
    patch.id = entityId;
  }

  const normalizedName = normalizeName(data.normalizedName ?? data.name);
  if (normalizedName.length > 0 && data.normalizedName !== normalizedName) {
    patch.normalizedName = normalizedName;
  }

  if (data.lastUsedAt == null) {
    patch.lastUsedAt =
      parseDate(data.createdAt) ?? parseDate(data.updatedAt) ?? new Date(0);
  }

  return Object.keys(patch).length === 0 ? null : patch;
}

export async function runEntityLastUsedAtBackfill({
  db,
  batchSize = 200,
  startAfterId,
}: {
  db: admin.firestore.Firestore;
  batchSize?: number;
  startAfterId?: string;
}): Promise<EntityLastUsedBackfillResult> {
  let query: admin.firestore.Query = db
    .collection("entities")
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(batchSize);
  if (startAfterId && startAfterId.length > 0) {
    query = query.startAfter(startAfterId);
  }

  const snapshot = await query.get();
  const batch = db.batch();
  let updated = 0;
  let lastCursor: string | null = null;

  for (const doc of snapshot.docs) {
    lastCursor = doc.id;
    const patch = buildEntityLastUsedAtBackfillPatch(doc.id, doc.data());
    if (patch == null) {
      continue;
    }
    batch.set(doc.ref, patch, { merge: true });
    updated += 1;
  }

  if (updated > 0) {
    await batch.commit();
  }

  return { scanned: snapshot.size, updated, lastCursor };
}

if (require.main === module) {
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
  const batchSize = Number(process.env.ENTITY_BACKFILL_BATCH_SIZE ?? 200);
  const startAfterId = process.env.ENTITY_BACKFILL_START_AFTER_ID;
  runEntityLastUsedAtBackfill({
    db: admin.firestore(),
    batchSize: Number.isFinite(batchSize) && batchSize > 0 ? batchSize : 200,
    startAfterId,
  })
    .then((result) => {
      console.log(JSON.stringify(result));
    })
    .catch((error: unknown) => {
      console.error(error);
      process.exitCode = 1;
    });
}
