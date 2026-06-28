"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.collectWorkerSummaryInitializationTargets = collectWorkerSummaryInitializationTargets;
exports.buildWorkerSummaryInitializationPayload = buildWorkerSummaryInitializationPayload;
exports.runWorkerAccountingSummaryInitialization = runWorkerAccountingSummaryInitialization;
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
const index_1 = require("./index");
function collectWorkerSummaryInitializationTargets(records) {
    const targets = new Map();
    let skippedInvalidTarget = 0;
    for (const record of records) {
        const workspaceId = `${record.data.workspaceId ?? ""}`.trim();
        const workerId = `${record.data.workerId ?? ""}`.trim();
        if (workspaceId.length === 0 || workerId.length === 0) {
            skippedInvalidTarget += 1;
            continue;
        }
        const key = `${workspaceId}_${workerId}`;
        if (!targets.has(key)) {
            targets.set(key, { key, workspaceId, workerId });
        }
    }
    return {
        targets: [...targets.values()].sort((a, b) => a.key.localeCompare(b.key)),
        skippedInvalidTarget,
    };
}
function buildWorkerSummaryInitializationPayload(input) {
    return (0, index_1.buildWorkerAccountingSummaryPayload)(input);
}
async function runWorkerAccountingSummaryInitialization({ db, batchSize = 500, dryRun = false, }) {
    const targets = new Map();
    let scanned = 0;
    let skippedInvalidTarget = 0;
    let lastCursor = null;
    while (true) {
        let query = db
            .collection("worker_accounting_records")
            .orderBy(firestore_1.FieldPath.documentId())
            .limit(batchSize);
        if (lastCursor != null) {
            query = query.startAfter(lastCursor);
        }
        const snapshot = await query.get();
        if (snapshot.empty) {
            break;
        }
        const result = collectWorkerSummaryInitializationTargets(snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() })));
        scanned += snapshot.size;
        skippedInvalidTarget += result.skippedInvalidTarget;
        for (const target of result.targets) {
            targets.set(target.key, target);
        }
        lastCursor = snapshot.docs[snapshot.docs.length - 1].id;
    }
    let summariesWritten = 0;
    let unresolvedLegacyPartials = 0;
    for (const target of [...targets.values()].sort((a, b) => a.key.localeCompare(b.key))) {
        const recordsSnap = await db
            .collection("worker_accounting_records")
            .where("workspaceId", "==", target.workspaceId)
            .where("workerId", "==", target.workerId)
            .get();
        const payload = buildWorkerSummaryInitializationPayload({
            workspaceId: target.workspaceId,
            workerId: target.workerId,
            records: recordsSnap.docs.map((doc) => doc.data()),
        });
        unresolvedLegacyPartials += Number(payload.unresolvedLegacyCount ?? 0);
        if (!dryRun) {
            await db
                .collection("worker_accounting_summaries")
                .doc(target.key)
                .set(payload, { merge: true });
            summariesWritten += 1;
        }
    }
    return {
        scanned,
        targetCount: targets.size,
        summariesWritten,
        skippedInvalidTarget,
        unresolvedLegacyPartials,
        dryRun,
    };
}
if (require.main === module) {
    if ((0, app_1.getApps)().length === 0) {
        (0, app_1.initializeApp)();
    }
    const batchSize = Number(process.env.WORKER_SUMMARY_INIT_BATCH_SIZE ?? 500);
    const dryRun = process.env.WORKER_SUMMARY_INIT_DRY_RUN === "true";
    runWorkerAccountingSummaryInitialization({
        db: (0, firestore_1.getFirestore)(),
        batchSize: Number.isFinite(batchSize) && batchSize > 0 ? batchSize : 500,
        dryRun,
    })
        .then((result) => {
        console.log(JSON.stringify(result));
    })
        .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
//# sourceMappingURL=worker_accounting_summary_initializer.js.map