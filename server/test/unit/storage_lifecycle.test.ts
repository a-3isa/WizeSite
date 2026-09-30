import assert from "node:assert/strict";
import test from "node:test";
import {
  chunkItems,
  collectAttachmentStoragePaths,
  isAllowedAttachmentStoragePath,
  isFirebaseStorageDownloadUrl,
} from "../../src/domain/storage_lifecycle";

test("chunkItems splits at 400", () => {
  const items = Array.from({length: 401}, (_, i) => i);
  const chunks = chunkItems(items, 400);
  assert.equal(chunks.length, 2);
  assert.equal(chunks[0].length, 400);
  assert.equal(chunks[1].length, 1);
});

test("collectAttachmentStoragePaths reads nested storagePath", () => {
  const paths = collectAttachmentStoragePaths([
    {
      data: () => ({
        attachments: [{storagePath: "attachments/u1/a.jpg"}, {storagePath: ""}],
      }),
    },
    {data: () => ({attachments: [{storagePath: "receipts/u1/b.pdf"}]})},
  ]);
  assert.deepEqual(paths, ["attachments/u1/a.jpg", "receipts/u1/b.pdf"]);
});

test("storage paths must be under attachments or receipts for the uid", () => {
  assert.equal(isAllowedAttachmentStoragePath("attachments/u1/x.jpg", "u1"), true);
  assert.equal(isAllowedAttachmentStoragePath("receipts/u1/x.jpg", "u1"), true);
  assert.equal(isAllowedAttachmentStoragePath("attachments/other/x.jpg", "u1"), false);
  assert.equal(isAllowedAttachmentStoragePath("../secrets", "u1"), false);
});

test("download URLs must be Firebase Storage HTTPS hosts", () => {
  assert.equal(
    isFirebaseStorageDownloadUrl(
      "https://firebasestorage.googleapis.com/v0/b/app/o/x",
    ),
    true,
  );
  assert.equal(isFirebaseStorageDownloadUrl("https://evil.example/x"), false);
  assert.equal(isFirebaseStorageDownloadUrl("not-a-url"), false);
});
