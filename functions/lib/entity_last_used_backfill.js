"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildEntityLastUsedAtBackfillPatch = buildEntityLastUsedAtBackfillPatch;
exports.runEntityLastUsedAtBackfill = runEntityLastUsedAtBackfill;
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
function normalizeName(value) {
    return `${value ?? ""}`.trim().toLowerCase().replace(/\s+/g, " ");
}
function parseDate(value) {
    if (value instanceof Date) {
        return value;
    }
    if (typeof value === "string" && value.trim().length > 0) {
        const parsed = new Date(value);
        return Number.isNaN(parsed.getTime()) ? null : parsed;
    }
    if (typeof value === "object" && value !== null) {
        const candidate = value;
        if (typeof candidate.toDate === "function") {
            const converted = candidate.toDate();
            return Number.isNaN(converted.getTime()) ? null : converted;
        }
    }
    return null;
}
function buildEntityLastUsedAtBackfillPatch(entityId, data) {
    const patch = {};
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
async function runEntityLastUsedAtBackfill({ db, batchSize = 200, startAfterId, }) {
    let query = db
        .collection("entities")
        .orderBy(firestore_1.FieldPath.documentId())
        .limit(batchSize);
    if (startAfterId && startAfterId.length > 0) {
        query = query.startAfter(startAfterId);
    }
    const snapshot = await query.get();
    const batch = db.batch();
    let updated = 0;
    let lastCursor = null;
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
    if ((0, app_1.getApps)().length === 0) {
        (0, app_1.initializeApp)();
    }
    const batchSize = Number(process.env.ENTITY_BACKFILL_BATCH_SIZE ?? 200);
    const startAfterId = process.env.ENTITY_BACKFILL_START_AFTER_ID;
    runEntityLastUsedAtBackfill({
        db: (0, firestore_1.getFirestore)(),
        batchSize: Number.isFinite(batchSize) && batchSize > 0 ? batchSize : 200,
        startAfterId,
    })
        .then((result) => {
        console.log(JSON.stringify(result));
    })
        .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
//# sourceMappingURL=entity_last_used_backfill.js.map