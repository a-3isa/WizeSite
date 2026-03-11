"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseExpenseFromTranscript = parseExpenseFromTranscript;
const confidence_1 = require("../utils/confidence");
const llm_extraction_service_1 = require("./llm_extraction.service");
const project_matcher_service_1 = require("./project_matcher.service");
const rule_extraction_service_1 = require("./rule_extraction.service");
const arabicNormalize_1 = require("../utils/arabicNormalize");
function clampNote(note) {
    if (!note) {
        return null;
    }
    const compact = note.replace(/\s+/g, " ").trim();
    if (!compact) {
        return null;
    }
    if (compact.length <= 120) {
        return compact;
    }
    return `${compact.slice(0, 117).trim()}...`;
}
function mergeConfidence(params) {
    const amount = params.fromLlm.amountUsed ? Math.max(params.fromRules.amount, 0.82) : params.fromRules.amount;
    const category = params.fromLlm.categoryUsed ?
        Math.max(params.fromRules.category, 0.72) :
        params.fromRules.category;
    const project = params.fromLlm.projectUsed ?
        Math.max(params.fromRules.project, params.projectConfidence) :
        params.fromRules.project;
    return (0, confidence_1.buildConfidenceScores)({ amount, category, project });
}
async function parseExpenseFromTranscript(input, llmExtractor = llm_extraction_service_1.extractExpenseByLlm) {
    const transcript = input.transcript.trim();
    const normalized = (0, arabicNormalize_1.normalizeTranscript)(transcript);
    const rules = (0, rule_extraction_service_1.extractExpenseByRules)({
        transcript,
        projects: input.projects,
        currency: input.currency,
    });
    if (!rules.shouldFallback) {
        return {
            transcript,
            parsed: rules.parsed,
            confidence: rules.confidence,
            source: "rules",
            needsConfirmation: true,
            storagePath: input.storagePath,
        };
    }
    try {
        const llm = await llmExtractor({
            openRouterApiKey: input.openRouterApiKey,
            model: input.openRouterModel,
            transcriptOriginal: transcript,
            transcriptNormalized: normalized,
            projects: input.projects,
            defaultCurrency: input.currency,
        });
        const llmProject = (0, llm_extraction_service_1.mapLlmProjectNameToProvided)({
            matchedProjectName: llm.matchedProjectName,
            projects: input.projects,
        });
        const llmProjectConfidence = llmProject.projectId == null ? 0 : (0, project_matcher_service_1.matchProjectFromTranscript)({
            normalizedTranscript: (0, arabicNormalize_1.normalizeTranscript)(llmProject.projectName ?? ""),
            projects: input.projects,
            threshold: 0.3,
        }).confidence;
        const amountFromLlm = rules.parsed.amount == null && llm.amount != null ? llm.amount : rules.parsed.amount;
        const canOverrideCategory = rules.parsed.category == null ||
            (rules.parsed.category === "other" && llm.category != null && llm.category !== "other");
        const categoryFromLlm = canOverrideCategory && llm.category != null ?
            llm.category :
            rules.parsed.category;
        const currency = llm.currency ?? rules.parsed.currency ?? input.currency;
        const projectId = rules.parsed.matchedProjectId ?? llmProject.projectId;
        const projectName = rules.parsed.matchedProjectName ?? llmProject.projectName;
        const note = clampNote(llm.note ?? rules.parsed.note);
        const mergedParsed = {
            amount: amountFromLlm,
            currency,
            category: categoryFromLlm,
            matchedProjectId: projectId,
            matchedProjectName: projectName,
            note,
        };
        const usedLlm = {
            amountUsed: rules.parsed.amount == null && llm.amount != null,
            categoryUsed: canOverrideCategory && llm.category != null,
            projectUsed: rules.parsed.matchedProjectId == null && llmProject.projectId != null,
        };
        const confidence = mergeConfidence({
            fromRules: rules.confidence,
            fromLlm: usedLlm,
            projectConfidence: llmProjectConfidence,
        });
        const source = usedLlm.amountUsed || usedLlm.categoryUsed || usedLlm.projectUsed ?
            (rules.parsed.amount == null && rules.parsed.category == null ? "llm" : "hybrid") :
            "rules";
        return {
            transcript,
            parsed: mergedParsed,
            confidence,
            source,
            needsConfirmation: true,
            storagePath: input.storagePath,
        };
    }
    catch {
        return {
            transcript,
            parsed: rules.parsed,
            confidence: rules.confidence,
            source: "rules",
            needsConfirmation: true,
            storagePath: input.storagePath,
        };
    }
}
//# sourceMappingURL=expense_parser.service.js.map