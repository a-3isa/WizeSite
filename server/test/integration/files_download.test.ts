/** T040: getAttachmentDownloadUrl + GET /v1/files/signed/* (contracts/files-api.md). */
import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, before, beforeEach, test } from "node:test";

import type { FastifyInstance } from "fastify";

import { buildApp } from "../../src/app";
import type { Sql } from "../../src/db/pool";
import { signedFileUrl } from "../../src/files/signing";
import { buildRegistry } from "../../src/rpc/registry";
import { authHeaders, resetDatabase, seedWorkspace, skipReason, stubVerifier, testSql } from "./helpers";

let sql: Sql;
let root: string;
let app: FastifyInstance;
const files = { root: "", signingKey: "test-signing-key-0123456789abcdef", publicUrl: "https://api.test" };
const receiptPath = "receipts/owner_1/إيصال مارس.jpg";
const bytes = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

before(async () => {
  if (skipReason) return;
  sql = testSql();
  root = await mkdtemp(path.join(os.tmpdir(), "wizesite-files-"));
  files.root = root;
  await mkdir(path.join(root, "receipts/owner_1"), { recursive: true });
  await writeFile(path.join(root, receiptPath), bytes);
  app = await buildApp({ sql, verifier: stubVerifier, registry: buildRegistry({ files }), logLevel: "silent", files });
  await app.ready();
});
after(async () => {
  if (app) await app.close();
  if (sql) await sql.end();
});
beforeEach(async () => {
  if (skipReason) return;
  await resetDatabase(sql);
  await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "owner_1", members: { member_1: "member" } });
  await seedWorkspace(sql, { workspaceId: "ws_2", ownerUid: "owner_2" });
});

async function requestUrl(uid: string, workspaceId: string, storagePath: string) {
  return app.inject({
    method: "POST",
    url: "/v1/rpc/getAttachmentDownloadUrl",
    headers: authHeaders(uid),
    payload: { data: { workspaceId, storagePath } },
  });
}

test("owner gets a 15-minute signed URL that serves the file with an Arabic filename", { skip: skipReason }, async () => {
  const res = await requestUrl("owner_1", "ws_1", receiptPath);
  assert.equal(res.statusCode, 200);
  const { downloadUrl, expiresInSeconds } = res.json().result;
  assert.equal(expiresInSeconds, 900);
  assert.ok(downloadUrl.startsWith("https://api.test/v1/files/signed/"));

  const file = await app.inject({ method: "GET", url: downloadUrl.replace("https://api.test", "") });
  assert.equal(file.statusCode, 200);
  assert.deepEqual(file.rawPayload, bytes);
  assert.equal(file.headers["content-type"], "image/jpeg");
  assert.equal(file.headers["cache-control"], "private, max-age=900");
  assert.match(
    `${file.headers["content-disposition"]}`,
    /^inline; filename\*=UTF-8''%D8%A5%D9%8A%D8%B5%D8%A7%D9%84%20%D9%85%D8%A7%D8%B1%D8%B3\.jpg$/,
  );
});

test("plain member is denied (financial roles only)", { skip: skipReason }, async () => {
  const res = await requestUrl("member_1", "ws_1", receiptPath);
  assert.equal(res.statusCode, 403);
  assert.equal(res.json().error.message, "Accounting access required to download attachments");
});

test("member of another workspace is denied", { skip: skipReason }, async () => {
  const res = await requestUrl("owner_2", "ws_1", receiptPath);
  assert.equal(res.statusCode, 403);
});

test("paths outside the attachment layout are rejected", { skip: skipReason }, async () => {
  for (const bad of ["../../etc/passwd", "voice-expenses/owner_1/a.m4a", "receipts/../secrets/x"]) {
    const res = await requestUrl("owner_1", "ws_1", bad);
    assert.equal(res.statusCode, 400, bad);
  }
});

test("tampered, expired and missing-file URLs are refused", { skip: skipReason }, async () => {
  const valid = signedFileUrl(files, receiptPath, Date.now());
  const tampered = valid.replace(/sig=[0-9a-f]{4}/, "sig=0000");
  assert.equal((await app.inject({ method: "GET", url: tampered.replace("https://api.test", "") })).statusCode, 403);

  const expired = signedFileUrl(files, receiptPath, Date.now() - 16 * 60 * 1000);
  assert.equal((await app.inject({ method: "GET", url: expired.replace("https://api.test", "") })).statusCode, 403);

  const otherPath = signedFileUrl(files, "receipts/owner_1/missing.jpg", Date.now());
  assert.equal((await app.inject({ method: "GET", url: otherPath.replace("https://api.test", "") })).statusCode, 404);
});

test("a signature for one path does not open another", { skip: skipReason }, async () => {
  const url = new URL(signedFileUrl(files, receiptPath, Date.now()));
  const swapped = `/v1/files/signed/receipts/owner_1/other.jpg${url.search}`;
  assert.equal((await app.inject({ method: "GET", url: swapped })).statusCode, 403);
});
