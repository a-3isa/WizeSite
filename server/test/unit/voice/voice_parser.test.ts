import assert from "node:assert/strict";
import test from "node:test";
import {buildConfidenceScores} from "../../../src/domain/voice/utils/confidence";
import {extractExpenseByRules} from "../../../src/domain/voice/services/rule_extraction.service";
import {matchProjectFromTranscript} from "../../../src/domain/voice/services/project_matcher.service";
import {parseExpenseFromTranscript} from "../../../src/domain/voice/services/expense_parser.service";
import {normalizeTranscript} from "../../../src/domain/voice/utils/arabicNormalize";
import {parseAmount} from "../../../src/domain/voice/utils/numbers";

test("converts Arabic numerals to western numbers", () => {
  const text = normalizeTranscript("دفعت ١٬٥٠٠ جنيه");
  assert.equal(parseAmount(text), 1500);
});

test("normalizes transcript spaces and Arabic alef forms", () => {
  const normalized = normalizeTranscript("  إشتريت   آجر   لمشروع  ");
  assert.equal(normalized, "اشتريت اجر لمشروع");
});

test("matches category keywords from rules", () => {
  const result = extractExpenseByRules({
    transcript: "Paid 3200 for steel in Villa October",
    projects: [
      {id: "p1", name: "Villa October"},
    ],
    currency: "EGP",
  });

  assert.equal(result.parsed.category, "materials");
  assert.equal(result.parsed.amount, 3200);
});

test("matches project by fuzzy logic", () => {
  const match = matchProjectFromTranscript({
    normalizedTranscript: "دفعت 2200 في مشروع عماره النرجس",
    projects: [
      {id: "p1", name: "Villa October"},
      {id: "p2", name: "عمارة النرجس"},
    ],
  });

  assert.equal(match.projectId, "p2");
  assert.ok(match.confidence >= 0.65);
});

test("calculates confidence scores", () => {
  const confidence = buildConfidenceScores({amount: 0.99, category: 0.95, project: 0.9});
  assert.ok(confidence.overall > 0.9);
});

test("uses fallback when amount is missing", () => {
  const result = extractExpenseByRules({
    transcript: "labor in Villa October",
    projects: [{id: "p1", name: "Villa October"}],
    currency: "EGP",
  });
  assert.equal(result.shouldFallback, true);
  assert.ok(result.fallbackReasons.includes("amount_missing"));
});

test("returns confirmation-ready response shape after fallback", async () => {
  const response = await parseExpenseFromTranscript(
    {
      transcript: "expense for project villa october",
      projects: [{id: "p1", name: "Villa October"}],
      currency: "EGP",
      storagePath: "voice-expenses/u1/sample.m4a",
      openRouterApiKey: "placeholder",
      openRouterModel: "openai/gpt-4o-mini",
    },
    async () => ({
      amount: 1800,
      currency: "EGP",
      category: "labor",
      matchedProjectName: "Villa October",
      note: "carpentry labor",
    }),
  );

  assert.equal(response.needsConfirmation, true);
  assert.equal(response.parsed.amount, 1800);
  assert.equal(response.parsed.category, "labor");
  assert.equal(response.parsed.matchedProjectId, "p1");
  assert.equal(response.storagePath, "voice-expenses/u1/sample.m4a");
  assert.ok(response.source === "llm" || response.source === "hybrid");
});
