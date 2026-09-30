"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FIRESTORE_WRITE_CHUNK = void 0;
exports.chunkItems = chunkItems;
exports.collectAttachmentStoragePaths = collectAttachmentStoragePaths;
exports.isAllowedAttachmentStoragePath = isAllowedAttachmentStoragePath;
exports.isFirebaseStorageDownloadUrl = isFirebaseStorageDownloadUrl;
exports.FIRESTORE_WRITE_CHUNK = 400;
function chunkItems(items, size = exports.FIRESTORE_WRITE_CHUNK) {
    if (size <= 0) {
        return [items];
    }
    const chunks = [];
    for (let i = 0; i < items.length; i += size) {
        chunks.push(items.slice(i, i + size));
    }
    return chunks;
}
function collectAttachmentStoragePaths(docs) {
    const paths = [];
    for (const doc of docs) {
        const attachments = doc.data().attachments;
        if (!Array.isArray(attachments)) {
            continue;
        }
        for (const item of attachments) {
            if (!item || typeof item !== "object") {
                continue;
            }
            const storagePath = `${item.storagePath ?? ""}`.trim();
            if (storagePath) {
                paths.push(storagePath);
            }
        }
    }
    return paths;
}
function isAllowedAttachmentStoragePath(storagePath, uid) {
    const path = storagePath.trim();
    if (!path || path.includes("..")) {
        return false;
    }
    if (uid) {
        return (path.startsWith(`attachments/${uid}/`) ||
            path.startsWith(`receipts/${uid}/`));
    }
    return /^(attachments|receipts)\/[^/]+\//.test(path);
}
function isFirebaseStorageDownloadUrl(url) {
    try {
        const parsed = new URL(url);
        if (parsed.protocol !== "https:") {
            return false;
        }
        const host = parsed.hostname.toLowerCase();
        return (host === "firebasestorage.googleapis.com" ||
            host.endsWith(".firebasestorage.app") ||
            host === "storage.googleapis.com" ||
            host.endsWith(".googleapis.com"));
    }
    catch {
        return false;
    }
}
//# sourceMappingURL=storage_lifecycle.js.map