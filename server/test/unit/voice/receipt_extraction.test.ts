/** Feature 005: AI-first receipt extraction (contracts/ai-extraction.md). The LLM is stubbed. */
import assert from "node:assert/strict";
import test from "node:test";

import { EXPENSE_CATEGORIES } from "../../../src/domain/money";
import {
  buildReceiptPrompt,
  extractReceipt,
  RECEIPT_CATEGORIES,
  type ReceiptLogger,
} from "../../../src/domain/voice/services/receipt_extraction.service";

const REFERENCE = "فاتورة سباكه شهر 10\n100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة";
const projects = [{ id: "p_villa_id", name: "فيلا التجمع" }];
const entities = [{ id: "e_hassan_id", name: "ورشة حسن" }];

type LlmJson = Record<string, unknown>;
const llmJson = (over: LlmJson = {}): LlmJson => ({
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
});

function stubFetch(body: LlmJson | string, status = 200) {
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
  const impl = (async (url: string, init: { body: string }) => {
    calls.push({ url, body: JSON.parse(init.body) });
    const content = typeof body === "string" ? body : JSON.stringify(body);
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status });
  }) as unknown as typeof fetch;
  return { impl, calls };
}

const silent: ReceiptLogger = { info: () => {}, warn: () => {} };

function run(text: string, fetchImpl: typeof fetch, logger: ReceiptLogger = silent) {
  return extractReceipt({
    text, projects, entities, currency: "EGP", today: "2026-10-19",
    openRouterApiKey: "k", model: "test/model", fetchImpl, logger,
  });
}

test("prompt carries text, normalized text, names, today and currency, never ids", () => {
  const prompt = buildReceiptPrompt({ text: "١٠٠ جنيه حنفية", projects, entities, currency: "EGP", today: "2026-10-19" });
  for (const part of ["١٠٠ جنيه حنفية", "100 جنيه حنفيه", "فيلا التجمع", "ورشة حسن", "2026-10-19", "EGP"]) {
    assert.ok(prompt.includes(part), `prompt should include ${part}`);
  }
  assert.ok(!prompt.includes("p_villa_id") && !prompt.includes("e_hassan_id"), "ids never sent to the model");
});

test("prompt carries every contract rule, including title numbers, stated total and quantity", () => {
  const prompt = buildReceiptPrompt({ text: "x", projects: [], entities: [], currency: "EGP", today: "2026-10-19" });
  assert.match(prompt, /شهر 10/, "rule 3: title numbers stay in the title");
  assert.match(prompt, /statedTotal/, "rule 6: stated total is not an item");
  assert.match(prompt, /line total/i, "rule 11: amount is the line total");
  assert.match(prompt, /2 حنفية بـ 200/, "rule 11 example");
});

test("request uses a strict schema whose category enum derives from the expense categories", async () => {
  const { impl, calls } = stubFetch(llmJson());
  await run(REFERENCE, impl);
  const format = calls[0].body.response_format as { json_schema: { strict: boolean; schema: { properties: { category: { enum: unknown[] } } } } };
  assert.equal(format.json_schema.strict, true);
  const expected = EXPENSE_CATEGORIES.filter((c) => !["labor", "worker", "payments"].includes(c));
  assert.deepEqual(RECEIPT_CATEGORIES, expected);
  assert.deepEqual(format.json_schema.schema.properties.category.enum, [...expected, null]);
});

test("reference phrase becomes title + three clean items", async () => {
  const { impl } = stubFetch(llmJson());
  const { proposal, source } = await run(REFERENCE, impl);
  assert.equal(source, "llm");
  assert.equal(proposal.title, "سباكه شهر 10");
  assert.deepEqual(proposal.items, [
    { name: "حنفية", amount: 100, quantity: null, needsReview: false },
    { name: "جلبه", amount: 50, quantity: null, needsReview: false },
    { name: "ماسورة", amount: 90, quantity: null, needsReview: false },
  ]);
  assert.equal(proposal.totalMismatch, false);
});

test("quantity is kept as information and never multiplies the amount", async () => {
  const { impl } = stubFetch(llmJson({ items: [{ name: "حنفية", amount: 200, quantity: 2, currency: null, uncertain: false }] }));
  const { proposal } = await run("2 حنفية بـ 200", impl);
  assert.deepEqual(proposal.items, [{ name: "حنفية", amount: 200, quantity: 2, needsReview: false }]);
});

test("post-processing flags, rounds, caps and maps names to ids", async () => {
  const items = [
    { name: "سلك", amount: -5, quantity: null, currency: null, uncertain: false },
    { name: "مفتاح", amount: 100.456, quantity: null, currency: null, uncertain: false },
    { name: "", amount: 30, quantity: null, currency: null, uncertain: false },
    { name: "لمبة", amount: 20, quantity: null, currency: "USD", uncertain: false },
    { name: "بريزة", amount: 15, quantity: null, currency: null, uncertain: true },
  ];
  const { impl } = stubFetch(llmJson({
    items, statedTotal: 250, date: "2026-10-22", matchedProjectName: "مشروع مجهول", supplierName: "ورشة حسن",
    category: "food", paymentStatus: "paid",
  }));
  const { proposal } = await run("x", impl);
  assert.deepEqual(proposal.items.map((i) => [i.amount, i.needsReview]), [
    [null, true], [100.46, false], [30, true], [20, true], [15, true],
  ]);
  assert.equal(proposal.items[2].name, null, "empty name becomes null");
  assert.equal(proposal.totalMismatch, true, "250 stated vs 165.46 summed");
  assert.equal(proposal.date, null, "3 days after today is rejected");
  assert.equal(proposal.projectId, null);
  assert.equal(proposal.entityId, "e_hassan_id");
  assert.equal(proposal.entityName, "ورشة حسن");
  assert.equal(proposal.category, null, "unknown category dropped");
  assert.equal(proposal.paymentStatus, "paid");
});

test("known project maps to its id; a valid recent date is kept", async () => {
  const { impl } = stubFetch(llmJson({ matchedProjectName: "فيلا التجمع", date: "2026-10-18", category: "materials" }));
  const { proposal } = await run("x", impl);
  assert.equal(proposal.projectId, "p_villa_id");
  assert.equal(proposal.date, "2026-10-18");
  assert.equal(proposal.category, "materials");
});

test("more than 100 items are capped and flagged as possibly several receipts", async () => {
  const many = Array.from({ length: 120 }, (_, i) => ({ name: `بند ${i}`, amount: 1, quantity: null, currency: null, uncertain: false }));
  const { impl } = stubFetch(llmJson({ items: many }));
  const { proposal } = await run("x", impl);
  assert.equal(proposal.items.length, 100);
  assert.equal(proposal.multipleReceiptsSuspected, true);
});

for (const [label, body, status] of [
  ["HTTP 500", llmJson(), 500],
  ["malformed JSON", "not json at all", 200],
] as const) {
  test(`${label} falls back to the rules extractor`, async () => {
    const { impl } = stubFetch(body, status);
    const { proposal, source } = await run("دفعت 3200 حديد", impl);
    assert.equal(source, "rules");
    assert.equal(proposal.items.length, 1);
    assert.equal(proposal.items[0].amount, 3200);
    assert.equal(proposal.items[0].needsReview, true);
  });
}

test("a throwing fetch falls back too, and rules with nothing give no items", async () => {
  const impl = (async () => {
    throw new Error("network down");
  }) as unknown as typeof fetch;
  const { proposal, source } = await run("مرحبا", impl);
  assert.equal(source, "rules");
  assert.deepEqual(proposal.items, []);
  assert.equal(proposal.title, null);
});

test("the raw text never reaches the logger", async () => {
  const lines: string[] = [];
  const spy: ReceiptLogger = {
    info: (msg, meta) => lines.push(`${msg} ${JSON.stringify(meta)}`),
    warn: (msg, meta) => lines.push(`${msg} ${JSON.stringify(meta)}`),
  };
  await run(REFERENCE, stubFetch(llmJson()).impl, spy);
  await run(REFERENCE, stubFetch("bad", 200).impl, spy);
  assert.ok(lines.length >= 2);
  for (const line of lines) {
    assert.ok(!line.includes("حنفية") && !line.includes("سباكه"), `leaked text: ${line}`);
  }
});
