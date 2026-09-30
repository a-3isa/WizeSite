import {
  DocumentReference,
  FieldValue,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export const IDEMPOTENCY_COLLECTION = "idempotency_keys";

export function normalizedClientMutationId(input: unknown): string {
  return `${input ?? ""}`.trim();
}

export function idempotencyDocId(
  workspaceId: string,
  kind: string,
  clientMutationId: string,
): string {
  const safeMutationId = clientMutationId.replace(/\//g, "_");
  return `${workspaceId}__${kind}__${safeMutationId}`;
}

export function idempotencyKeyRef(
  db: Firestore,
  workspaceId: string,
  kind: string,
  clientMutationId: string,
) {
  return db
    .collection(IDEMPOTENCY_COLLECTION)
    .doc(idempotencyDocId(workspaceId, kind, clientMutationId));
}

function existingDocIdFromSnap(data: {docId?: unknown} | undefined): string {
  return `${data?.docId ?? ""}`.trim();
}

export async function readExistingMutation(
  db: Firestore,
  workspaceId: string,
  kind: string,
  clientMutationId: unknown,
): Promise<{id: string; clientMutationId: string} | null> {
  const mutationId = normalizedClientMutationId(clientMutationId);
  if (!mutationId) {
    return null;
  }
  const snap = await idempotencyKeyRef(
    db,
    workspaceId,
    kind,
    mutationId,
  ).get();
  if (!snap.exists) {
    return null;
  }
  const docId = existingDocIdFromSnap(snap.data());
  if (!docId) {
    throw new HttpsError(
      "failed-precondition",
      "Corrupt idempotency key",
    );
  }
  return {id: docId, clientMutationId: mutationId};
}

/**
 * Returns the existing document id when this mutation was already claimed.
 * Otherwise writes the key and returns null so the caller can insert.
 */
export async function claimMutationInTx(
  tx: Transaction,
  db: Firestore,
  input: {
    workspaceId: string;
    kind: string;
    clientMutationId: string;
    docId: string;
  },
): Promise<string | null> {
  const mutationId = normalizedClientMutationId(input.clientMutationId);
  if (!mutationId) {
    return null;
  }
  const ref = idempotencyKeyRef(
    db,
    input.workspaceId,
    input.kind,
    mutationId,
  );
  const snap = await tx.get(ref);
  if (snap.exists) {
    const existingId = existingDocIdFromSnap(snap.data());
    if (!existingId) {
      throw new HttpsError(
        "failed-precondition",
        "Corrupt idempotency key",
      );
    }
    return existingId;
  }
  tx.set(ref, {
    workspaceId: input.workspaceId,
    kind: input.kind,
    clientMutationId: mutationId,
    docId: input.docId,
    createdAt: FieldValue.serverTimestamp(),
  });
  return null;
}

export type QuotaGuard = {
  counterRef: DocumentReference;
  field: string;
  max: number;
  apply: boolean;
  onExceeded: () => never;
  seedFrom?: (tx: Transaction) => Promise<number>;
};

export async function commitIdempotentCreate(
  db: Firestore,
  input: {
    workspaceId: string;
    kind: string;
    clientMutationId: unknown;
    newDocId: string;
    write: (tx: Transaction) => void;
    quota?: QuotaGuard;
  },
): Promise<{id: string; clientMutationId: string}> {
  const mutationId = normalizedClientMutationId(input.clientMutationId);
  let replayedId: string | null = null;
  await db.runTransaction(async (tx) => {
    const keyRef = mutationId
      ? idempotencyKeyRef(db, input.workspaceId, input.kind, mutationId)
      : null;
    const keySnap = keyRef ? await tx.get(keyRef) : null;
    const quotaSnap =
      input.quota?.apply === true
        ? await tx.get(input.quota.counterRef)
        : null;

    if (keySnap?.exists) {
      const existingId = existingDocIdFromSnap(keySnap.data());
      if (!existingId) {
        throw new HttpsError(
          "failed-precondition",
          "Corrupt idempotency key",
        );
      }
      replayedId = existingId;
      return;
    }

    if (input.quota?.apply === true) {
      const raw = quotaSnap?.data()?.[input.quota.field];
      const current =
        raw == null && input.quota.seedFrom
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
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    input.write(tx);
  });
  if (replayedId) {
    return {id: replayedId, clientMutationId: mutationId};
  }
  return {id: input.newDocId, clientMutationId: mutationId};
}
