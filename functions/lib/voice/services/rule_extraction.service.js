"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.extractExpenseByRules = extractExpenseByRules;
const project_matcher_service_1 = require("./project_matcher.service");
const confidence_1 = require("../utils/confidence");
const numbers_1 = require("../utils/numbers");
const arabicNormalize_1 = require("../utils/arabicNormalize");
const CATEGORY_KEYWORDS = {
    labor: [
        "عماله",
        "عامل",
        "نجار",
        "نجارين",
        "سباك",
        "كهربائي",
        "نقاش",
        "مبيض",
        "carpenter",
        "labor",
        "plumber",
        "electrician",
        "painter",
        "mason",
    ],
    materials: [
        "مواد",
        "اسمنت",
        "حديد",
        "طوب",
        "رمل",
        "زلط",
        "خرسانه",
        "cement",
        "steel",
        "bricks",
        "sand",
        "gravel",
        "concrete",
    ],
    equipment: [
        "معدات",
        "حفار",
        "ونش",
        "خلاطه",
        "equipment",
        "excavator",
        "crane",
        "mixer",
    ],
    transport: [
        "نقل",
        "شحن",
        "عربيه",
        "truck",
        "transport",
        "delivery",
    ],
    other: [],
};
function detectCategory(normalizedTranscript) {
    for (const [category, keywords] of Object.entries(CATEGORY_KEYWORDS)) {
        if (keywords.length === 0) {
            continue;
        }
        const matches = keywords.filter((keyword) => normalizedTranscript.includes(keyword));
        if (matches.length > 0) {
            return {
                category,
                confidence: 0.95,
                matchedKeywords: matches,
            };
        }
    }
    const words = normalizedTranscript.split(" ").filter((x) => x.trim().length > 1);
    if (words.length >= 2) {
        return {
            category: "other",
            confidence: 0.4,
            matchedKeywords: [],
        };
    }
    return {
        category: null,
        confidence: 0,
        matchedKeywords: [],
    };
}
function compactNote(input) {
    const normalized = input.replace(/[.,;:!?]/g, " ").replace(/\s+/g, " ").trim();
    if (normalized.length === 0) {
        return null;
    }
    if (normalized.length <= 90) {
        return normalized;
    }
    return `${normalized.slice(0, 87).trim()}...`;
}
function extractNote(params) {
    let working = (0, arabicNormalize_1.normalizeTranscript)(params.originalTranscript);
    if (params.amountToken) {
        const escaped = params.amountToken.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        working = working.replace(new RegExp(escaped, "g"), " ");
    }
    if (params.matchedProjectName) {
        const projectNormalized = (0, arabicNormalize_1.normalizeTranscript)(params.matchedProjectName).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        working = working.replace(new RegExp(projectNormalized, "g"), " ");
    }
    for (const keyword of params.matchedKeywords) {
        const escaped = keyword.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        working = working.replace(new RegExp(escaped, "g"), " ");
    }
    working = working
        .replace(/\b(دفعت|دفعنا|paid|for|in|project|مشروع|في|على)\b/g, " ")
        .replace(/\s+/g, " ")
        .trim();
    if (working.length < 2) {
        return compactNote(params.originalTranscript);
    }
    return compactNote(working);
}
function shouldFallback(params) {
    const reasons = [];
    if (params.amount == null) {
        reasons.push("amount_missing");
    }
    if (params.category == null) {
        reasons.push("category_missing");
    }
    if (params.projectConfidence < 0.6) {
        reasons.push("project_low_confidence");
    }
    const tokenCount = params.normalizedTranscript.split(" ").filter((x) => x.length > 0).length;
    if (tokenCount < 2) {
        reasons.push("transcript_ambiguous");
    }
    return {
        needsFallback: reasons.length > 0,
        reasons,
    };
}
function extractExpenseByRules(params) {
    const originalTranscript = params.transcript.trim();
    const normalized = (0, arabicNormalize_1.normalizeTranscript)(originalTranscript);
    const amountToken = (0, numbers_1.extractAmountCandidate)(normalized);
    const amount = (0, numbers_1.parseAmount)(normalized);
    const categoryResult = detectCategory(normalized);
    const projectMatch = (0, project_matcher_service_1.matchProjectFromTranscript)({
        normalizedTranscript: normalized,
        projects: params.projects,
    });
    const note = extractNote({
        originalTranscript,
        normalizedTranscript: normalized,
        amountToken,
        matchedProjectName: projectMatch.projectName,
        matchedKeywords: categoryResult.matchedKeywords,
    });
    const fallback = shouldFallback({
        amount,
        category: categoryResult.category,
        projectConfidence: projectMatch.confidence,
        normalizedTranscript: normalized,
    });
    return {
        parsed: {
            amount,
            currency: amount == null ? null : params.currency,
            category: categoryResult.category,
            matchedProjectId: projectMatch.projectId,
            matchedProjectName: projectMatch.projectName,
            note,
        },
        confidence: (0, confidence_1.buildConfidenceScores)({
            amount: amount == null ? 0 : 0.99,
            category: categoryResult.confidence,
            project: projectMatch.confidence,
        }),
        shouldFallback: fallback.needsFallback,
        fallbackReasons: fallback.reasons,
        normalizedTranscript: normalized,
    };
}
//# sourceMappingURL=rule_extraction.service.js.map