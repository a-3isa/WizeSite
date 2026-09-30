/** T064: POST /v1/files, limits copied from storage.rules; path is always {kind}/{callerUid}/…. */
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, beforeEach, test } from "node:test";

import type { FastifyInstance } from "fastify";

import { buildApp } from "../../src/app";
import type { Sql } from "../../src/db/pool";
import { authHeaders, resetDatabase, skipReason, stubVerifier, testSql } from "./helpers";

let sql: Sql;
let app: FastifyInstance;
let root: string;

before(async () => {
  if (skipReason) return;
  sql = testSql();
  root = await mkdtemp(path.join(tmpdir(), "upload-"));
  app = await buildApp({
    sql,
    verifier: stubVerifier,
    files: { root, signingKey: "k".repeat(32), publicUrl: "https://api.test" },
    logLevel: "silent",
  });
});
after(async () => {
  await app?.close();
  if (sql) await sql.end();
});
beforeEach(async () => {
  if (!skipReason) await resetDatabase(sql);
});

function multipart(fields: Record<string, string>, file?: { name: string; type: string; body: Buffer }) {
  const boundary = "----wizesite-test-boundary";
  const parts: Buffer[] = [];
  for (const [key, value] of Object.entries(fields)) {
    parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${key}"\r\n\r\n${value}\r\n`));
  }
  if (file) {
    parts.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${file.name}"\r\nContent-Type: ${file.type}\r\n\r\n`,
      ),
      file.body,
      Buffer.from("\r\n"),
    );
  }
  parts.push(Buffer.from(`--${boundary}--\r\n`));
  return { payload: Buffer.concat(parts), contentType: `multipart/form-data; boundary=${boundary}` };
}

async function upload(uid: string, key: string, kind: string, file?: { name: string; type: string; body: Buffer }) {
  const { payload, contentType } = multipart({ kind }, file);
  return app.inject({
    method: "POST",
    url: "/v1/files",
    headers: { ...authHeaders(uid, key), "content-type": contentType },
    payload,
  });
}

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);

test("upload: stored under {kind}/{uid}/, sha256 and size returned, file is private", { skip: skipReason }, async () => {
  const res = await upload("u1", "k1", "receipts", { name: "إيصال.jpg", type: "image/jpeg", body: jpeg });
  assert.equal(res.statusCode, 201);
  const body = res.json();
  assert.match(body.storagePath, /^receipts\/u1\/[0-9a-f-]{36}\.jpg$/);
  assert.equal(body.contentType, "image/jpeg");
  assert.equal(body.sizeBytes, jpeg.length);
  assert.equal(body.sha256, createHash("sha256").update(jpeg).digest("hex"));
  const stored = path.join(root, body.storagePath);
  assert.deepEqual(await readFile(stored), jpeg);
  assert.equal((await stat(stored)).mode & 0o777, process.platform === "win32" ? (await stat(stored)).mode & 0o777 : 0o600);
});

test("upload: same idempotency key returns the first result, one file", { skip: skipReason }, async () => {
  const first = await upload("u1", "same", "attachments", { name: "a.pdf", type: "application/pdf", body: Buffer.from("%PDF-1") });
  const second = await upload("u1", "same", "attachments", { name: "a.pdf", type: "application/pdf", body: Buffer.from("%PDF-1") });
  assert.equal(second.statusCode, 201);
  assert.equal(second.json().storagePath, first.json().storagePath);
});

test("upload: storage.rules limits (type per kind, 10 MB, known kinds)", { skip: skipReason }, async () => {
  const bad = async (kind: string, type: string, body: Buffer, message: string) => {
    const res = await upload("u1", `k-${kind}-${type}-${body.length}`, kind, { name: "f", type, body });
    assert.equal(res.statusCode, 400, `${kind} ${type}`);
    assert.equal(res.json().error.message, message);
  };
  await bad("receipts", "image/webp", jpeg, "Unsupported file type");
  await bad("profile-photos", "image/gif", jpeg, "Unsupported file type");
  await bad("voice-expenses", "image/jpeg", jpeg, "Unsupported file type");
  await bad("secrets", "image/jpeg", jpeg, "Unsupported upload kind");
  await bad("receipts", "image/jpeg", Buffer.alloc(10 * 1024 * 1024 + 1), "File is too large");
  const voice = await upload("u1", "v1", "voice-expenses", { name: "v.m4a", type: "audio/mp4", body: Buffer.from("ok") });
  assert.equal(voice.statusCode, 201);
});

test("upload: needs a signed-in caller, an idempotency key and a file", { skip: skipReason }, async () => {
  const noAuth = await app.inject({ method: "POST", url: "/v1/files", payload: {} });
  assert.equal(noAuth.statusCode, 401);
  const { payload, contentType } = multipart({ kind: "receipts" }, { name: "a.jpg", type: "image/jpeg", body: jpeg });
  const noKey = await app.inject({
    method: "POST",
    url: "/v1/files",
    headers: { ...authHeaders("u1"), "content-type": contentType },
    payload,
  });
  assert.equal(noKey.statusCode, 400);
  const noFile = await upload("u1", "nofile", "receipts");
  assert.equal(noFile.statusCode, 400);
});
