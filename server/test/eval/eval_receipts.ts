/**
 * Feature 005 live AI eval (quickstart §2, SC-002/SC-003). Calls the real model through
 * extractReceipt for every case in receipts.jsonl and fails (exit 1) when item accuracy < 85%,
 * a title number becomes an item amount, or p95 latency > 8 s. Needs OPENROUTER_API_KEY
 * (server/.env or the environment); costs a few cents per run. Run: npm run eval:receipts
 */
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

import { extractReceipt } from "../../src/domain/voice/services/receipt_extraction.service";
import type { ProposalItem } from "../../src/domain/voice/types/expense";
import { normalizeTranscript } from "../../src/domain/voice/utils/arabicNormalize";

type Expected = { name: string; amount: number; quantity?: number };
type Case = { id: string; input: string; expected: { title: string | null; items: Expected[] } };

const MIN_ACCURACY = 0.85;
const MAX_P95_MS = 8000;

// tsc does not copy .jsonl into dist, so read it from the source tree.
const casesFile = path.resolve(__dirname, "../../../test/eval/receipts.jsonl");
const envFile = path.resolve(__dirname, "../../../.env");
if (existsSync(envFile) && !process.env.OPENROUTER_API_KEY) {
  process.loadEnvFile(envFile);
}

const key = (s: string | null) => normalizeTranscript(s ?? "").replace(/^ال/, "");
const sameName = (a: string | null, b: string) => {
  const x = key(a);
  const y = key(b);
  return x.length > 0 && (x === y || x.includes(y) || y.includes(x));
};
const cents = (n: number | null) => Math.round((n ?? 0) * 100);

/** Expected items matched one-to-one against actual items (name + amount, and quantity if set). */
function matchItems(expected: Expected[], actual: ProposalItem[]): number {
  const used = new Set<number>();
  let hits = 0;
  for (const exp of expected) {
    const index = actual.findIndex((act, i) =>
      !used.has(i) && cents(act.amount) === cents(exp.amount) && sameName(act.name, exp.name) &&
      (exp.quantity === undefined || act.quantity === exp.quantity));
    if (index >= 0) {
      used.add(index);
      hits++;
    }
  }
  return hits;
}

/** A number that qualifies the expected title ("شهر 10") turned into an item amount. */
function titleNumberViolations(c: Case, actual: ProposalItem[]): number[] {
  const titleNumbers = (normalizeTranscript(c.expected.title ?? "").match(/\d+/g) ?? []).map(Number);
  const expectedAmounts = new Set(c.expected.items.map((i) => cents(i.amount)));
  return titleNumbers.filter((n) => actual.some((a) => cents(a.amount) === n * 100) && !expectedAmounts.has(n * 100));
}

function percentile(values: number[], p: number): number {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)] ?? 0;
}

async function main(): Promise<void> {
  const apiKey = process.env.OPENROUTER_API_KEY?.trim() ?? "";
  const model = process.env.OPENROUTER_MODEL?.trim() || "openai/gpt-4o-mini";
  if (!apiKey) {
    console.error("OPENROUTER_API_KEY is not set (server/.env or environment).");
    process.exit(2);
  }
  const cases = readFileSync(casesFile, "utf8").split(/\r?\n/).filter((l) => l.trim()).map((l) => JSON.parse(l) as Case);
  const silent = { info: () => {}, warn: () => {} };
  let expectedTotal = 0;
  let hitTotal = 0;
  let titleHits = 0;
  let violations = 0;
  let fallbacks = 0;
  const latencies: number[] = [];
  console.log(`model=${model} cases=${cases.length}`);
  for (const c of cases) {
    const started = Date.now();
    const { proposal, source } = await extractReceipt({
      text: c.input, projects: [], entities: [], currency: "EGP", today: "2026-10-19",
      openRouterApiKey: apiKey, model, logger: silent,
    });
    latencies.push(Date.now() - started);
    const hits = matchItems(c.expected.items, proposal.items);
    const bad = titleNumberViolations(c, proposal.items);
    const titleOk = c.expected.title === null || sameName(proposal.title, c.expected.title);
    expectedTotal += c.expected.items.length;
    hitTotal += hits;
    titleHits += titleOk ? 1 : 0;
    violations += bad.length;
    fallbacks += source === "rules" ? 1 : 0;
    console.log([
      c.id.padEnd(24), `items ${hits}/${c.expected.items.length}`.padEnd(12), titleOk ? "title ok " : "title ✗  ",
      source === "rules" ? "FALLBACK" : "", bad.length ? `TITLE-NUMBER ${bad.join(",")}` : "",
      `${latencies[latencies.length - 1]}ms`,
    ].join(" "));
  }
  const accuracy = expectedTotal ? hitTotal / expectedTotal : 0;
  const p50 = percentile(latencies, 50);
  const p95 = percentile(latencies, 95);
  console.log("");
  console.log(`item accuracy   ${(accuracy * 100).toFixed(1)}% (${hitTotal}/${expectedTotal}), gate ≥ ${MIN_ACCURACY * 100}%`);
  console.log(`title matches   ${titleHits}/${cases.length} (informational)`);
  console.log(`title-number    ${violations} violation(s), gate 0`);
  console.log(`rules fallbacks ${fallbacks}`);
  console.log(`latency         p50 ${p50}ms, p95 ${p95}ms, gate p95 ≤ ${MAX_P95_MS}ms`);
  const failed = accuracy < MIN_ACCURACY || violations > 0 || p95 > MAX_P95_MS;
  console.log(failed ? "RESULT: FAIL" : "RESULT: PASS");
  process.exit(failed ? 1 : 0);
}

void main();
