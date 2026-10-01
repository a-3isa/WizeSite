/** Public profile-photo links (owner's decision): only uploaded avatars, nothing else. */
import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";

import type { FastifyInstance } from "fastify";

import { buildApp } from "../../src/app";
import type { Sql } from "../../src/db/pool";
import { skipReason, stubVerifier, testSql } from "./helpers";

const AVATAR = "profile-photos/u1/0f8fad5b-d9cb-469f-a165-70867728950e.jpg";
let sql: Sql;
let app: FastifyInstance;

before(async () => {
  if (skipReason) return;
  sql = testSql();
  const root = await mkdtemp(path.join(tmpdir(), "avatars-"));
  for (const file of [AVATAR, "receipts/u1/0f8fad5b-d9cb-469f-a165-70867728950e.jpg"]) {
    await mkdir(path.dirname(path.join(root, file)), { recursive: true });
    await writeFile(path.join(root, file), Buffer.from([0xff, 0xd8, 0xff]));
  }
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

test("an uploaded profile photo is public and cacheable, without sign-in", { skip: skipReason }, async () => {
  const res = await app.inject({ method: "GET", url: `/v1/public/${AVATAR}` });
  assert.equal(res.statusCode, 200);
  assert.equal(res.headers["content-type"], "image/jpeg");
  assert.equal(res.headers["cache-control"], "public, max-age=31536000, immutable");
  assert.equal(res.rawPayload.length, 3);
});

test("receipts, traversal and other names are not served", { skip: skipReason }, async () => {
  for (const url of [
    "/v1/public/receipts/u1/0f8fad5b-d9cb-469f-a165-70867728950e.jpg",
    "/v1/public/profile-photos/u1/../../receipts/u1/0f8fad5b-d9cb-469f-a165-70867728950e.jpg",
    "/v1/public/profile-photos/u1/avatar.jpg",
    "/v1/public/profile-photos/u1/0f8fad5b-d9cb-469f-a165-70867728950e.pdf",
    "/v1/public/profile-photos/u2/0f8fad5b-d9cb-469f-a165-70867728950e.jpg",
  ]) {
    const res = await app.inject({ method: "GET", url });
    assert.equal(res.statusCode, 404, url);
  }
});
