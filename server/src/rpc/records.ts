import type { Sql } from "../db/pool";
import { parseTimestamp } from "../domain/accounting";
import { RpcError as HttpsError } from "../domain/errors";
import { isAllowedAttachmentStoragePath, isFirebaseStorageDownloadUrl } from "../domain/storage_lifecycle";
import { requireString } from "./validation";

/**
 * Helpers shared by the record-writing RPCs (projects, expenses, payments, workers), ported from
 * functions/src/index.ts and idempotency.ts.
 */

/** parseTimestamp → Date (timestamptz), null when absent or invalid. */
export function toDate(input: unknown): Date | null {
  return parseTimestamp(input)?.toDate() ?? null;
}

/**
 * Fields Firestore stored on the document but that have no column: kept in `legacy` exactly like
 * migrated rows, so both look the same to clients.
 */
export function legacyFields(data: Record<string, unknown>, extra: Record<string, unknown> = {}): Record<string, unknown> {
  const out: Record<string, unknown> = { ...extra };
  const created = toDate(data.clientCreatedAt);
  const updated = toDate(data.clientUpdatedAt);
  if (created) out.clientCreatedAt = created.toISOString();
  if (updated) out.clientUpdatedAt = updated.toISOString();
  return out;
}

/** Blank → NULL, so (workspace_id, client_mutation_id) stays unique only for real ids. */
export function mutationIdOf(data: Record<string, unknown>): string | null {
  const id = `${data.clientMutationId ?? ""}`.trim();
  return id.length > 0 ? id : null;
}

/**
 * readExistingMutation: a record already created for this clientMutationId in this workspace.
 * Replaces the Firestore idempotency_keys docs with the table's own unique key.
 */
export async function existingMutation(
  sql: Sql,
  table: "projects" | "expenses" | "payments" | "workers" | "worker_entries",
  workspaceId: string,
  clientMutationId: string | null,
): Promise<{ id: string; clientMutationId: string } | null> {
  if (!clientMutationId) {
    return null;
  }
  const [row] = await sql<{ id: string }[]>`
    SELECT id FROM ${sql(table)}
    WHERE workspace_id = ${workspaceId} AND client_mutation_id = ${clientMutationId}`;
  return row ? { id: row.id, clientMutationId } : null;
}

function deriveAttachmentType(contentType: string, fileName: string): string {
  const normalized = contentType.toLowerCase();
  if (normalized.startsWith("image/")) return "image";
  if (normalized === "application/pdf") return "pdf";
  if (normalized.startsWith("video/")) return "video";
  if (fileName.toLowerCase().endsWith(".pdf")) return "pdf";
  return "file";
}

/**
 * normalizeAttachmentItem. One deliberate difference: files uploaded to the new file store have
 * no permanent download URL (they are read through getAttachmentDownloadUrl), so `downloadUrl`
 * is optional here; when present it must still be a Firebase Storage URL (legacy uploads).
 */
function normalizeAttachmentItem(raw: unknown, key: string): Record<string, unknown> {
  if (!raw || typeof raw !== "object") {
    throw new HttpsError("invalid-argument", `Invalid attachment item: ${key}`);
  }
  const attachment = raw as Record<string, unknown>;
  const id = requireString(attachment, "id");
  const fileName = requireString(attachment, "fileName");
  const urlValue =
    typeof attachment.downloadUrl === "string" && attachment.downloadUrl.trim().length > 0
      ? attachment.downloadUrl.trim()
      : typeof attachment.url === "string" && attachment.url.trim().length > 0
        ? attachment.url.trim()
        : "";
  if (urlValue.length > 0 && !isFirebaseStorageDownloadUrl(urlValue)) {
    throw new HttpsError("invalid-argument", `Invalid attachment download URL host for ${key}`);
  }
  const uploadedAt = toDate(attachment.uploadedAt);
  if (uploadedAt == null) {
    throw new HttpsError("invalid-argument", `Invalid or missing uploadedAt for ${key}`);
  }
  const contentType =
    typeof attachment.contentType === "string" && attachment.contentType.trim().length > 0
      ? attachment.contentType.trim()
      : typeof attachment.mimeType === "string" && attachment.mimeType.trim().length > 0
        ? attachment.mimeType.trim()
        : "application/octet-stream";
  const storagePath = typeof attachment.storagePath === "string" ? attachment.storagePath.trim() : "";
  if (!isAllowedAttachmentStoragePath(storagePath)) {
    throw new HttpsError("invalid-argument", `Invalid attachment storage path for ${key}`);
  }
  const type =
    typeof attachment.type === "string" && attachment.type.trim().length > 0
      ? attachment.type.trim()
      : deriveAttachmentType(contentType, fileName);
  const normalized: Record<string, unknown> = {
    id,
    fileName,
    ...(urlValue ? { url: urlValue, downloadUrl: urlValue } : {}),
    storagePath,
    contentType,
    mimeType: contentType,
    type,
    uploadedAt: uploadedAt.toISOString(),
  };
  if (attachment.size != null) {
    const size = Number(attachment.size);
    if (!Number.isFinite(size)) {
      throw new HttpsError("invalid-argument", `Invalid attachment size for ${key}`);
    }
    normalized.size = size;
  }
  return normalized;
}

export function ensureAttachmentItems(data: Record<string, unknown>, key: string): Array<Record<string, unknown>> {
  const raw = data[key];
  if (raw == null) {
    return [];
  }
  if (!Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", `Invalid attachments format: ${key}`);
  }
  return raw.map((item, index) => normalizeAttachmentItem(item, `${key}[${index}]`));
}

/** hasContractValue: zero and absent both mean "not set". */
export function hasContractValue(contractValue: unknown): boolean {
  if (contractValue === null || contractValue === undefined) {
    return false;
  }
  return Number(contractValue) > 0;
}
