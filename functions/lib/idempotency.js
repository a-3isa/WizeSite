"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.IDEMPOTENCY_COLLECTION = void 0;
exports.normalizedClientMutationId = normalizedClientMutationId;
exports.idempotencyDocId = idempotencyDocId;
exports.idempotencyKeyRef = idempotencyKeyRef;
exports.readExistingMutation = readExistingMutation;
exports.claimMutationInTx = claimMutationInTx;
exports.commitIdempotentCreate = commitIdempotentCreate;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
exports.IDEMPOTENCY_COLLECTION = "idempotency_keys";
function normalizedClientMutationId(input) {
    return `${input ?? ""}`.trim();
}
function idempotencyDocId(workspaceId, kind, clientMutationId) {
    const safeMutationId = clientMutationId.replace(/\//g, "_");
    return `${workspaceId}__${kind}__${safeMutationId}`;
}
function idempotencyKeyRef(db, workspaceId, kind, clientMutationId) {
    return db
        .collection(exports.IDEMPOTENCY_COLLECTION)
        .doc(idempotencyDocId(workspaceId, kind, clientMutationId));
}
function existingDocIdFromSnap(data) {
    return `${data?.docId ?? ""}`.trim();
}
async function readExistingMutation(db, workspaceId, kind, clientMutationId) {
    const mutationId = normalizedClientMutationId(clientMutationId);
    if (!mutationId) {
        return null;
    }
    const snap = await idempotencyKeyRef(db, workspaceId, kind, mutationId).get();
    if (!snap.exists) {
        return null;
    }
    const docId = existingDocIdFromSnap(snap.data());
    if (!docId) {
        throw new https_1.HttpsError("failed-precondition", "Corrupt idempotency key");
    }
    return { id: docId, clientMutationId: mutationId };
}
/**
 * Returns the existing document id when this mutation was already claimed.
 * Otherwise writes the key and returns null so the caller can insert.
 */
async function claimMutationInTx(tx, db, input) {
    const mutationId = normalizedClientMutationId(input.clientMutationId);
    if (!mutationId) {
        return null;
    }
    const ref = idempotencyKeyRef(db, input.workspaceId, input.kind, mutationId);
    const snap = await tx.get(ref);
    if (snap.exists) {
        const existingId = existingDocIdFromSnap(snap.data());
        if (!existingId) {
            throw new https_1.HttpsError("failed-precondition", "Corrupt idempotency key");
        }
        return existingId;
    }
    tx.set(ref, {
        workspaceId: input.workspaceId,
        kind: input.kind,
        clientMutationId: mutationId,
        docId: input.docId,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    return null;
}
async function commitIdempotentCreate(db, input) {
    const mutationId = normalizedClientMutationId(input.clientMutationId);
    let replayedId = null;
    await db.runTransaction(async (tx) => {
        const keyRef = mutationId
            ? idempotencyKeyRef(db, input.workspaceId, input.kind, mutationId)
            : null;
        const keySnap = keyRef ? await tx.get(keyRef) : null;
        const quotaSnap = input.quota?.apply === true
            ? await tx.get(input.quota.counterRef)
            : null;
        if (keySnap?.exists) {
            const existingId = existingDocIdFromSnap(keySnap.data());
            if (!existingId) {
                throw new https_1.HttpsError("failed-precondition", "Corrupt idempotency key");
            }
            replayedId = existingId;
            return;
        }
        if (input.quota?.apply === true) {
            const raw = quotaSnap?.data()?.[input.quota.field];
            const current = raw == null && input.quota.seedFrom
                ? await input.quota.seedFrom(tx)
                : Number(raw ?? 0);
            if (current + 1 > input.quota.max) {
                input.quota.onExceeded();
            }
        }
        if (keyRef && mutationId) {
            tx.set(keyRef, {
                workspaceId: input.workspaceId,
                kind: input.kind,
                clientMutationId: mutationId,
                docId: input.newDocId,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        input.write(tx);
    });
    if (replayedId) {
        return { id: replayedId, clientMutationId: mutationId };
    }
    return { id: input.newDocId, clientMutationId: mutationId };
}
//# sourceMappingURL=idempotency.js.map