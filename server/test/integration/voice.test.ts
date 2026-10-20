/** T065: processVoiceExpense reads the uploaded audio from FILES_ROOT; OpenRouter is mocked. */
import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, afterEach, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { organizeExpenseTextForUser, processVoiceExpenseForUser, voiceRpcs } from "../../src/rpc/voice";
import { authHeaders, buildTestApp, resetDatabase, seedWorkspace, skipReason, testSql } from "./helpers";

let sql: Sql;
let root: string;
const realFetch = globalThis.fetch;
let requests: Array<{ model: string; hasAudio: boolean }>;
let lastPrompt: unknown;

function openRouter(transcript: string, extraction: Record<string, unknown>) {
  requests = [];
  globalThis.fetch = (async (_url: unknown, init?: { body?: string }) => {
    const body = JSON.parse(`${init?.body ?? "{}"}`);
    const hasAudio = JSON.stringify(body.messages).includes("input_audio");
    requests.push({ model: body.model, hasAudio });
    if (!hasAudio) lastPrompt = body.messages;
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

/** Feature 005: the strict receipt-extraction JSON the model returns (contracts/ai-extraction.md). */
function receipt(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    title: "سباكه شهر 10",
    items: [
      { name: "حنفية", amount: 100, quantity: null, currency: null, uncertain: false },
      { name: "جلبه", amount: 50, quantity: null, currency: null, uncertain: false },
      { name: "ماسورة", amount: 90, quantity: null, currency: null, uncertain: false },
    ],
    matchedProjectName: null,
    category: null,
    supplierName: null,
    date: null,
    paymentStatus: null,
    currency: "EGP",
    statedTotal: null,
    multipleReceiptsSuspected: false,
    ...over,
  };
}

const deps = () => ({
  files: { root },
  openRouter: { apiKey: "test-key", model: "openai/gpt-4o-mini", transcriptionModel: "openai/gpt-audio-mini" },
});

test("transcribes the caller's own audio and matches a live project", { skip: skipReason }, async () => {
  openRouter("اشتريت أسمنت بخمسة آلاف جنيه لمشروع فيلا سكنيه", receipt({
    title: null,
    items: [{ name: "أسمنت", amount: 5000, quantity: null, currency: null, uncertain: false }],
    category: "materials",
    matchedProjectName: "فيلا سكنيه",
  }));
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

// ---------------------------------------------------------------- feature 005: proposals

test("voice keeps every legacy field and adds the receipt proposal", { skip: skipReason }, async () => {
  openRouter("فاتورة سباكه شهر 10، 100 جنيه حنفية، 50 جنيه جلبه، 90 جنيه ماسورة", receipt());
  const result = await processVoiceExpenseForUser(sql, deps(), "u1", { storagePath: "voice-expenses/u1/clip.m4a" });
  for (const key of ["transcript", "parsed", "confidence", "source", "needsConfirmation", "storagePath"]) {
    assert.ok(key in result, `legacy field ${key} kept`);
  }
  assert.equal(result.source, "llm");
  assert.equal(result.parsed.amount, 240, "older clients still see the receipt total");
  assert.equal(result.parsed.note, "سباكه شهر 10");
  assert.equal(result.proposal?.title, "سباكه شهر 10");
  assert.deepEqual(result.proposal?.items.map((i) => [i.name, i.amount]), [["حنفية", 100], ["جلبه", 50], ["ماسورة", 90]]);
});

test("voice falls back to rules when the AI fails, and honors the client's today", { skip: skipReason }, async () => {
  requests = [];
  globalThis.fetch = (async (_url: unknown, init?: { body?: string }) => {
    const body = JSON.parse(`${init?.body ?? "{}"}`);
    if (JSON.stringify(body.messages).includes("input_audio")) {
      return new Response(JSON.stringify({ choices: [{ message: { content: "دفعت 3200 حديد" } }] }), { status: 200 });
    }
    requests.push({ model: body.model, hasAudio: false });
    return new Response("boom", { status: 500 });
  }) as typeof fetch;
  const result = await processVoiceExpenseForUser(sql, deps(), "u1", { storagePath: "voice-expenses/u1/clip.m4a", today: "2026-10-19" });
  assert.equal(result.source, "rules");
  assert.equal(result.parsed.amount, 3200);
  assert.equal(result.proposal?.items.length, 1);
  assert.equal(result.proposal?.items[0].needsReview, true);

  openRouter("امبارح سباكه", receipt({ date: "2026-10-18" }));
  const dated = await processVoiceExpenseForUser(sql, deps(), "u1", { storagePath: "voice-expenses/u1/clip.m4a", today: "2026-10-19" });
  assert.equal(dated.proposal?.date, "2026-10-18");
  openRouter("بكره سباكه", receipt({ date: "2026-10-25" }));
  const future = await processVoiceExpenseForUser(sql, deps(), "u1", { storagePath: "voice-expenses/u1/clip.m4a", today: "2026-10-19" });
  assert.equal(future.proposal?.date, null);
});

const REFERENCE_TEXT = "فاتورة سباكه شهر 10\n100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة";

test("organizeExpenseText returns the contract response for the reference text", { skip: skipReason }, async () => {
  await sql`INSERT INTO entities (id, workspace_id, name, type) VALUES ('e_hassan', 'ws_1', 'ورشة حسن', 'supplier')`;
  openRouter("", receipt({ supplierName: "ورشة حسن", matchedProjectName: "برج", paymentStatus: "paid" }));
  const result = await organizeExpenseTextForUser(sql, deps(), "u1", { workspaceId: "ws_1", text: REFERENCE_TEXT, today: "2026-10-19" });
  assert.equal(result.text, REFERENCE_TEXT);
  assert.equal(result.source, "llm");
  assert.equal(result.needsConfirmation, true);
  assert.equal(result.proposal.title, "سباكه شهر 10");
  assert.equal(result.proposal.items.length, 3);
  assert.equal(result.proposal.projectId, "p_tower");
  assert.equal(result.proposal.entityId, "e_hassan");
  assert.equal(result.proposal.paymentStatus, "paid");
  assert.equal(requests.length, 1, "one AI call, no transcription");
});

test("organizeExpenseText validates input, role and configuration", { skip: skipReason }, async () => {
  await sql`INSERT INTO memberships (id, workspace_id, user_uid, role) VALUES ('ws_1_entry', 'ws_1', 'entry', 'entryOnly')`;
  openRouter("", receipt());
  const call = (uid: string, data: Record<string, unknown>, d = deps()) => organizeExpenseTextForUser(sql, d, uid, data);
  const code = (expected: string, message?: string) => (error: { code?: string; message?: string }) =>
    error.code === expected && (message === undefined || error.message === message);
  await assert.rejects(call("u1", { workspaceId: "ws_1", text: "   " }), code("invalid-argument", "text must be between 1 and 4000 characters"));
  await assert.rejects(call("u1", { workspaceId: "ws_1", text: "x".repeat(4001) }), code("invalid-argument", "text must be between 1 and 4000 characters"));
  await assert.rejects(call("entry", { workspaceId: "ws_1", text: REFERENCE_TEXT }), code("permission-denied"));
  await assert.rejects(
    call("u1", { workspaceId: "ws_1", text: REFERENCE_TEXT }, { ...deps(), openRouter: { ...deps().openRouter, apiKey: "" } }),
    code("failed-precondition", "OPENROUTER_API_KEY is not configured"),
  );
});

test("organizeExpenseText uses the requested workspace's projects, not the active one", { skip: skipReason }, async () => {
  await seedWorkspace(sql, { workspaceId: "ws_2", ownerUid: "u1" });
  await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('p_other', 'ws_2', 'مول')`;
  openRouter("", receipt({ matchedProjectName: "مول" }));
  const result = await organizeExpenseTextForUser(sql, deps(), "u1", { workspaceId: "ws_2", text: REFERENCE_TEXT });
  assert.equal(result.proposal.projectId, "p_other");
  const prompt = JSON.stringify(lastPrompt);
  assert.ok(prompt.includes("مول") && !prompt.includes("فيلا سكنيه"), "only ws_2 project names are sent");
});

test("organizeExpenseText retried with the same idempotency key calls the AI once", { skip: skipReason }, async () => {
  openRouter("", receipt());
  const app = await buildTestApp(sql, voiceRpcs(deps()));
  const send = () => app.inject({
    method: "POST",
    url: "/v1/rpc/organizeExpenseText",
    headers: authHeaders("u1", "organize-key-1"),
    payload: { data: { workspaceId: "ws_1", text: REFERENCE_TEXT, today: "2026-10-19" } },
  });
  const first = await send();
  const second = await send();
  assert.equal(first.statusCode, 200);
  assert.deepEqual(second.json(), first.json());
  assert.equal(requests.length, 1);
  await app.close();
});
