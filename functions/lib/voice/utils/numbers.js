"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.extractAmountCandidate = extractAmountCandidate;
exports.parseAmount = parseAmount;
const arabicNormalize_1 = require("./arabicNormalize");
const AMOUNT_PATTERN = /\b\d{1,3}(?:[,\s]\d{3})*(?:\.\d+)?\b|\b\d+(?:\.\d+)?\b/g;
function cleanNumericToken(token) {
    return token.replace(/,/g, "").replace(/\s+/g, "");
}
function extractAmountCandidate(input) {
    const normalized = (0, arabicNormalize_1.convertArabicDigitsToWestern)(input).replace(/٬/g, ",").replace(/٫/g, ".");
    const matches = normalized.match(AMOUNT_PATTERN);
    if (!matches || matches.length === 0) {
        return null;
    }
    for (const match of matches) {
        const cleaned = cleanNumericToken(match);
        const parsed = Number(cleaned);
        if (Number.isFinite(parsed) && parsed > 0) {
            return cleaned;
        }
    }
    return null;
}
function parseAmount(input) {
    const candidate = extractAmountCandidate(input);
    if (!candidate) {
        return null;
    }
    const parsed = Number(candidate);
    if (!Number.isFinite(parsed) || parsed <= 0) {
        return null;
    }
    return parsed;
}
//# sourceMappingURL=numbers.js.map