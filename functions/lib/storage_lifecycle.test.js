"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const storage_lifecycle_1 = require("./storage_lifecycle");
(0, node_test_1.default)("chunkItems splits at 400", () => {
    const items = Array.from({ length: 401 }, (_, i) => i);
    const chunks = (0, storage_lifecycle_1.chunkItems)(items, 400);
    strict_1.default.equal(chunks.length, 2);
    strict_1.default.equal(chunks[0].length, 400);
    strict_1.default.equal(chunks[1].length, 1);
});
(0, node_test_1.default)("collectAttachmentStoragePaths reads nested storagePath", () => {
    const paths = (0, storage_lifecycle_1.collectAttachmentStoragePaths)([
        {
            data: () => ({
                attachments: [{ storagePath: "attachments/u1/a.jpg" }, { storagePath: "" }],
            }),
        },
        { data: () => ({ attachments: [{ storagePath: "receipts/u1/b.pdf" }] }) },
    ]);
    strict_1.default.deepEqual(paths, ["attachments/u1/a.jpg", "receipts/u1/b.pdf"]);
});
(0, node_test_1.default)("storage paths must be under attachments or receipts for the uid", () => {
    strict_1.default.equal((0, storage_lifecycle_1.isAllowedAttachmentStoragePath)("attachments/u1/x.jpg", "u1"), true);
    strict_1.default.equal((0, storage_lifecycle_1.isAllowedAttachmentStoragePath)("receipts/u1/x.jpg", "u1"), true);
    strict_1.default.equal((0, storage_lifecycle_1.isAllowedAttachmentStoragePath)("attachments/other/x.jpg", "u1"), false);
    strict_1.default.equal((0, storage_lifecycle_1.isAllowedAttachmentStoragePath)("../secrets", "u1"), false);
});
(0, node_test_1.default)("download URLs must be Firebase Storage HTTPS hosts", () => {
    strict_1.default.equal((0, storage_lifecycle_1.isFirebaseStorageDownloadUrl)("https://firebasestorage.googleapis.com/v0/b/app/o/x"), true);
    strict_1.default.equal((0, storage_lifecycle_1.isFirebaseStorageDownloadUrl)("https://evil.example/x"), false);
    strict_1.default.equal((0, storage_lifecycle_1.isFirebaseStorageDownloadUrl)("not-a-url"), false);
});
//# sourceMappingURL=storage_lifecycle.test.js.map