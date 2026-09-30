export const FIRESTORE_WRITE_CHUNK = 400;

export function chunkItems<T>(items: T[], size = FIRESTORE_WRITE_CHUNK): T[][] {
  if (size <= 0) {
    return [items];
  }
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

export function collectAttachmentStoragePaths(
  docs: Array<{data: () => Record<string, unknown>}>,
): string[] {
  const paths: string[] = [];
  for (const doc of docs) {
    const attachments = doc.data().attachments;
    if (!Array.isArray(attachments)) {
      continue;
    }
    for (const item of attachments) {
      if (!item || typeof item !== "object") {
        continue;
      }
      const storagePath = `${(item as Record<string, unknown>).storagePath ?? ""}`.trim();
      if (storagePath) {
        paths.push(storagePath);
      }
    }
  }
  return paths;
}

export function isAllowedAttachmentStoragePath(
  storagePath: string,
  uid?: string,
): boolean {
  const path = storagePath.trim();
  if (!path || path.includes("..")) {
    return false;
  }
  if (uid) {
    return (
      path.startsWith(`attachments/${uid}/`) ||
      path.startsWith(`receipts/${uid}/`)
    );
  }
  return /^(attachments|receipts)\/[^/]+\//.test(path);
}

export function isFirebaseStorageDownloadUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:") {
      return false;
    }
    const host = parsed.hostname.toLowerCase();
    return (
      host === "firebasestorage.googleapis.com" ||
      host.endsWith(".firebasestorage.app") ||
      host === "storage.googleapis.com" ||
      host.endsWith(".googleapis.com")
    );
  } catch {
    return false;
  }
}
