"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const confidence_1 = require("./utils/confidence");
const rule_extraction_service_1 = require("./services/rule_extraction.service");
const project_matcher_service_1 = require("./services/project_matcher.service");
const expense_parser_service_1 = require("./services/expense_parser.service");
const arabicNormalize_1 = require("./utils/arabicNormalize");
const numbers_1 = require("./utils/numbers");
const process_voice_expense_1 = require("./process_voice_expense");
(0, node_test_1.default)("converts Arabic numerals to western numbers", () => {
    const text = (0, arabicNormalize_1.normalizeTranscript)("دفعت ١٬٥٠٠ جنيه");
    strict_1.default.equal((0, numbers_1.parseAmount)(text), 1500);
});
(0, node_test_1.default)("normalizes transcript spaces and Arabic alef forms", () => {
    const normalized = (0, arabicNormalize_1.normalizeTranscript)("  إشتريت   آجر   لمشروع  ");
    strict_1.default.equal(normalized, "اشتريت اجر لمشروع");
});
(0, node_test_1.default)("matches category keywords from rules", () => {
    const result = (0, rule_extraction_service_1.extractExpenseByRules)({
        transcript: "Paid 3200 for steel in Villa October",
        projects: [
            { id: "p1", name: "Villa October" },
        ],
        currency: "EGP",
    });
    strict_1.default.equal(result.parsed.category, "materials");
    strict_1.default.equal(result.parsed.amount, 3200);
});
(0, node_test_1.default)("matches project by fuzzy logic", () => {
    const match = (0, project_matcher_service_1.matchProjectFromTranscript)({
        normalizedTranscript: "دفعت 2200 في مشروع عماره النرجس",
        projects: [
            { id: "p1", name: "Villa October" },
            { id: "p2", name: "عمارة النرجس" },
        ],
    });
    strict_1.default.equal(match.projectId, "p2");
    strict_1.default.ok(match.confidence >= 0.65);
});
(0, node_test_1.default)("calculates confidence scores", () => {
    const confidence = (0, confidence_1.buildConfidenceScores)({ amount: 0.99, category: 0.95, project: 0.9 });
    strict_1.default.ok(confidence.overall > 0.9);
});
(0, node_test_1.default)("uses fallback when amount is missing", () => {
    const result = (0, rule_extraction_service_1.extractExpenseByRules)({
        transcript: "labor in Villa October",
        projects: [{ id: "p1", name: "Villa October" }],
        currency: "EGP",
    });
    strict_1.default.equal(result.shouldFallback, true);
    strict_1.default.ok(result.fallbackReasons.includes("amount_missing"));
});
(0, node_test_1.default)("returns confirmation-ready response shape after fallback", async () => {
    const response = await (0, expense_parser_service_1.parseExpenseFromTranscript)({
        transcript: "expense for project villa october",
        projects: [{ id: "p1", name: "Villa October" }],
        currency: "EGP",
        storagePath: "voice-expenses/u1/sample.m4a",
        openRouterApiKey: "placeholder",
        openRouterModel: "openai/gpt-4o-mini",
    }, async () => ({
        amount: 1800,
        currency: "EGP",
        category: "labor",
        matchedProjectName: "Villa October",
        note: "carpentry labor",
    }));
    strict_1.default.equal(response.needsConfirmation, true);
    strict_1.default.equal(response.parsed.amount, 1800);
    strict_1.default.equal(response.parsed.category, "labor");
    strict_1.default.equal(response.parsed.matchedProjectId, "p1");
    strict_1.default.equal(response.storagePath, "voice-expenses/u1/sample.m4a");
    strict_1.default.ok(response.source === "llm" || response.source === "hybrid");
});
(0, node_test_1.default)("rejects invalid App Check tokens on the voice HTTP fallback", async () => {
    await strict_1.default.rejects(() => (0, process_voice_expense_1.verifyVoiceHttpAppCheck)(undefined, async () => {
        throw new Error("should not verify missing tokens");
    }), (error) => {
        strict_1.default.equal(error.code, "failed-precondition");
        return true;
    });
    await strict_1.default.rejects(() => (0, process_voice_expense_1.verifyVoiceHttpAppCheck)("invalid-token", async () => {
        throw new Error("invalid app check token");
    }), (error) => {
        strict_1.default.equal(error.code, "failed-precondition");
        return true;
    });
});
//# sourceMappingURL=voice_parser.test.js.map