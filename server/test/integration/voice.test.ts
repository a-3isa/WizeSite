/** T065: processVoiceExpense reads the uploaded audio from FILES_ROOT; OpenRouter is mocked. */
import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, afterEach, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { processVoiceExpenseForUser } from "../../src/rpc/voice";
import { resetDatabase, seedWorkspace, skipReason, testSql } from "./helpers";

let sql: Sql;
let root: string;
const realFetch = globalThis.fetch;
let requests: Array<{ model: string; hasAudio: boolean }>;

function openRouter(transcript: string, extraction: Record<string, unknown>) {
  requests = [];
  globalThis.fetch = (async (_url: unknown, init?: { body?: string }) => {
    const body = JSON.parse(`${init?.body ?? "{}"}`);
    const hasAudio = JSON.stringify(body.messages).includes("input_audio");
    requests.push({ model: body.model, hasAudio });
    const content = hasAudio ? transcript : JSON.stringify(extraction);
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 });
  }) as typeof fetch;
}

before(async () => {
  if (skipReason) return;
  sql = testSql();
  root = await mkdtemp(path.join(tmpdir(), "voice-"));
  await mkdir(path.join(root, "voice-expenses/u1"), { recursive: true });
  await writeFile(path.join(root, "voice-expenses/u1/clip.m4a"), Buffer.from("fake-audio"));
});
after(async () => {
  if (sql) await sql.end();
});
beforeEach(async () => {
  if (!skipReason) {
    await resetDatabase(sql);
    await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "u1" });
    await sql`INSERT INTO user_profiles (uid, active_workspace_id) VALUES ('u1', 'ws_1')`;
    await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('p_villa', 'ws_1', 'فيلا سكنيه'), ('p_tower', 'ws_1', 'برج')`;
    await sql`INSERT INTO projects (id, workspace_id, name, is_archived) VALUES ('p_old', 'ws_1', 'قديم', true)`;
  }
});
afterEach(() => {
  globalThis.fetch = realFetch;
});

const deps = () => ({
  files: { root },
  openRouter: { apiKey: "test-key", model: "openai/gpt-4o-mini", transcriptionModel: "openai/gpt-audio-mini" },
});

test("transcribes the caller's own audio and matches a live project", { skip: skipReason }, async () => {
  openRouter("اشتريت أسمنت بخمسة آلاف جنيه لمشروع فيلا سكنيه", {
    amount: 5000,
    currency: "EGP",
    category: "materials",
    matchedProjectName: "فيلا سكنيه",
    note: "أسمنت",
  });
  const result = await processVoiceExpenseForUser(sql, deps(), "u1", {
    storagePath: "voice-expenses/u1/clip.m4a",
    currency: "egp",
    languageHint: "ar-EG",
  });
  assert.equal(result.transcript, "اشتريت أسمنت بخمسة آلاف جنيه لمشروع فيلا سكنيه");
  assert.equal(result.parsed.amount, 5000);
  assert.equal(result.parsed.matchedProjectId, "p_villa");
  assert.equal(result.storagePath, "voice-expenses/u1/clip.m4a");
  assert.equal(requests[0].model, "openai/gpt-audio-mini");
  assert.equal(requests[0].hasAudio, true);
});

test("someone else's audio, a missing file and a missing key are refused", { skip: skipReason }, async () => {
  openRouter("x", {});
  await assert.rejects(
    processVoiceExpenseForUser(sql, deps(), "u2", { storagePath: "voice-expenses/u1/clip.m4a" }),
    (error: { code?: string; message?: string }) =>
      error.code === "permission-denied" && error.message === "storagePath is not owned by current user",
  );
  await assert.rejects(
    processVoiceExpenseForUser(sql, deps(), "u1", { storagePath: "voice-expenses/u1/missing.m4a" }),
    (error: { code?: string }) => error.code === "not-found",
  );
  await assert.rejects(
    processVoiceExpenseForUser(sql, { ...deps(), openRouter: { ...deps().openRouter, apiKey: "" } }, "u1", {
      storagePath: "voice-expenses/u1/clip.m4a",
    }),
    (error: { code?: string; message?: string }) =>
      error.code === "failed-precondition" && error.message === "OPENROUTER_API_KEY is not configured",
  );
  await assert.rejects(
    processVoiceExpenseForUser(sql, deps(), "u1", { storagePath: " " }),
    (error: { message?: string }) => error.message === "storagePath is required",
  );
});

test("an empty transcription is refused as before (failed-precondition)", { skip: skipReason }, async () => {
  requests = [];
  globalThis.fetch = (async () =>
    new Response(JSON.stringify({ choices: [{ message: { content: "   " } }] }), { status: 200 })) as unknown as typeof fetch;
  await assert.rejects(
    processVoiceExpenseForUser(sql, deps(), "u1", { storagePath: "voice-expenses/u1/clip.m4a" }),
    (error: { code?: string; message?: string }) => error.code === "failed-precondition" && error.message === "Transcription was empty",
  );
});
